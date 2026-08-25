defmodule Ted.Index do
  @moduledoc "Database access shared by service health and agent authentication."

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias Ted.AgentAuth.{AccessToken, Event, Registration}
  alias Ted.Repo

  @registration_lock 7_566_567_577_261_413_932

  @spec context(keyword()) :: module()
  def context(opts \\ []), do: Keyword.get(opts, :repo, Repo)

  @spec health(module()) :: :ok | {:error, term()}
  def health(repo \\ Repo) do
    case SQL.query(repo, "SELECT 1", []) do
      {:ok, %{rows: [[1]]}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec agent_auth(module(), term()) :: term()
  def agent_auth(
        repo,
        {:create_rate_limited_registration, registration, since, address_limit, global_limit}
      ) do
    transaction(repo, fn ->
      with :ok <- acquire_registration_lock(repo),
           :ok <-
             enforce_registration_limits(
               repo,
               since,
               registration.registration_address,
               address_limit,
               global_limit
             ) do
        insert_registration(repo, registration)
      end
    end)
  end

  def agent_auth(repo, {:registration_by_claim_token, hash}),
    do: find_registration(repo, :claim_token_hash, hash)

  def agent_auth(repo, {:registration_by_claim_attempt, hash}),
    do: find_registration(repo, :claim_attempt_token_hash, hash)

  def agent_auth(repo, {:registration_by_id, id}), do: find_registration(repo, :id, id)

  def agent_auth(repo, {:claimed_registration_by_provider, issuer, subject}) do
    result =
      repo.one(
        from(registration in Registration,
          where:
            registration.provider_issuer == ^issuer and
              registration.provider_subject == ^subject and registration.status == "claimed",
          order_by: [desc: registration.created_at],
          limit: 1
        )
      )

    if is_nil(result),
      do: {:error, :not_found},
      else: {:ok, result |> Map.from_struct() |> Map.drop([:__meta__])}
  end

  def agent_auth(repo, {:provider_assertion_seen, issuer, jti}) do
    query =
      from(registration in Registration,
        where: registration.provider_issuer == ^issuer and registration.provider_jti == ^jti
      )

    if repo.exists?(query), do: {:error, :replay_detected}, else: :ok
  end

  def agent_auth(repo, {:start_anonymous_claim, id, attributes, current_time}) do
    repo.transaction(fn ->
      registration =
        repo.one(
          from(registration in Registration,
            where: registration.id == ^id,
            lock: "FOR UPDATE"
          )
        )

      start_locked_anonymous_claim(repo, registration, attributes, current_time)
    end)
    |> case do
      {:ok, {:value, registration}} -> {:ok, registration}
      {:ok, {:domain_error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def agent_auth(repo, {:mark_polled, id, polled_at}) do
    repo.update_all(from(registration in Registration, where: registration.id == ^id),
      set: [last_polled_at: polled_at]
    )

    :ok
  end

  def agent_auth(repo, {:record_claim_address, id, address}) do
    repo.update_all(
      from(registration in Registration,
        where: registration.id == ^id and registration.status == "pending"
      ),
      set: [claim_address: address]
    )

    :ok
  end

  def agent_auth(repo, {:record_sign_in_failure, id, address, attempt_limit}) do
    repo.transaction(fn ->
      registration =
        repo.one(
          from(registration in Registration, where: registration.id == ^id, lock: "FOR UPDATE")
        )

      case record_locked_sign_in_failure(repo, registration, address, attempt_limit) do
        :ok -> :ok
        {:error, reason} when is_atom(reason) -> {:domain_error, reason}
        {:error, reason} -> repo.rollback(reason)
      end
    end)
    |> normalize_domain_transaction()
  end

  def agent_auth(
        repo,
        {:confirm_claim, id, code_hash, user_id, claimed_at, email_verified, address,
         attempt_limit}
      ) do
    repo.transaction(fn ->
      registration =
        repo.one(
          from(registration in Registration, where: registration.id == ^id, lock: "FOR UPDATE")
        )

      case confirm_locked_claim(
             repo,
             registration,
             code_hash,
             user_id,
             claimed_at,
             email_verified,
             address,
             attempt_limit
           ) do
        :ok -> :ok
        {:error, reason} when is_atom(reason) -> {:domain_error, reason}
        {:error, reason} -> repo.rollback(reason)
      end
    end)
    |> normalize_domain_transaction()
  end

  def agent_auth(repo, {:expire_registration, id, expired_at}) do
    transaction(repo, fn ->
      {count, _records} =
        repo.update_all(
          from(registration in Registration,
            where: registration.id == ^id and registration.status == "pending"
          ),
          set: [status: "expired"]
        )

      if count == 1,
        do: insert_agent_event(repo, id, "registration.expired", %{expired_at: expired_at}),
        else: :ok
    end)
  end

  def agent_auth(repo, {:expire_due_registrations, expired_at}) do
    transaction(repo, fn ->
      registrations =
        repo.all(
          from(registration in Registration,
            where: registration.status == "pending" and registration.expires_at <= ^expired_at,
            lock: "FOR UPDATE SKIP LOCKED"
          )
        )

      with :ok <- expire_registrations(repo, registrations, expired_at) do
        {:ok, length(registrations)}
      end
    end)
  end

  def agent_auth(repo, {:put_access_token, token}) do
    attrs = Map.drop(token, [:value])

    transaction(repo, fn ->
      with {:ok, _record} <- repo.insert(struct(AccessToken, attrs)) do
        insert_agent_event(repo, token.registration_id, "token.issued", %{scope: token.scopes})
      end
    end)
  end

  def agent_auth(repo, {:access_token, hash}) do
    result =
      repo.one(
        from(access_token in AccessToken,
          join: registration in Registration,
          on: registration.id == access_token.registration_id,
          where: access_token.token_hash == ^hash,
          select: %{
            scopes: access_token.scopes,
            expires_at: access_token.expires_at,
            revoked_at: access_token.revoked_at,
            resource: access_token.resource,
            registration_id: registration.id,
            registration_status: registration.status,
            registration_type: registration.registration_type,
            claim_email: registration.claim_email,
            user_id: registration.claimed_by_user_id
          }
        )
      )

    if is_nil(result), do: {:error, :not_found}, else: {:ok, result}
  end

  def agent_auth(repo, {:revoke_access_token, hash, revoked_at}) do
    transaction(repo, fn -> revoke_access_token(repo, hash, revoked_at) end)
  end

  def agent_auth(repo, {:revoke_user_access_tokens, user_id, revoked_at}) do
    transaction(repo, fn ->
      registrations =
        repo.all(
          from(registration in Registration,
            where:
              registration.claimed_by_user_id == ^user_id and registration.status == "claimed",
            lock: "FOR UPDATE"
          )
        )

      tokens =
        repo.all(
          from(access_token in AccessToken,
            join: registration in Registration,
            on: registration.id == access_token.registration_id,
            where:
              registration.claimed_by_user_id == ^user_id and is_nil(access_token.revoked_at),
            select: %{hash: access_token.token_hash, registration_id: registration.id},
            lock: "FOR UPDATE OF a0"
          )
        )

      with :ok <- revoke_user_tokens(repo, tokens, revoked_at),
           :ok <- revoke_registrations(repo, registrations, revoked_at) do
        {:ok, length(tokens)}
      end
    end)
  end

  def agent_auth(repo, {:revoke_registration_access_tokens, registration_id, revoked_at}) do
    transaction(repo, fn ->
      tokens =
        repo.all(
          from(access_token in AccessToken,
            where:
              access_token.registration_id == ^registration_id and is_nil(access_token.revoked_at),
            lock: "FOR UPDATE"
          )
        )

      Enum.reduce_while(tokens, :ok, fn token, :ok ->
        revoke_registration_token(repo, token, registration_id, revoked_at)
      end)
    end)
  end

  def agent_auth(repo, {:revoke_provider_identity, issuer, subject, revoked_at}) do
    transaction(repo, fn ->
      registrations =
        repo.all(
          from(registration in Registration,
            where:
              registration.provider_issuer == ^issuer and
                registration.provider_subject == ^subject and registration.status != "revoked",
            lock: "FOR UPDATE"
          )
        )

      Enum.reduce_while(registrations, {:ok, 0}, fn registration, {:ok, count} ->
        revoke_provider_registration(repo, registration, issuer, subject, revoked_at, count)
      end)
    end)
  end

  def agent_auth(repo, {:record_event, registration_id, name, metadata}),
    do: insert_agent_event(repo, registration_id, name, metadata)

  def agent_auth(_repo, _operation), do: {:error, :unsupported_operation}

  defp start_locked_anonymous_claim(
         repo,
         %{
           registration_type: "anonymous",
           status: "pending",
           expires_at: expires_at,
           claim_attempt_expires_at: attempt_expires_at
         } = registration,
         attributes,
         current_time
       )
       when expires_at > current_time and
              (is_nil(attempt_expires_at) or attempt_expires_at <= current_time) do
    with {:ok, updated} <-
           registration |> Ecto.Changeset.change(attributes) |> repo.update(),
         :ok <-
           insert_agent_event(repo, registration.id, "claim.requested", %{
             email: attributes.claim_email
           }),
         :ok <- insert_agent_event(repo, registration.id, "user_code.minted", %{}) do
      {:value, updated |> Map.from_struct() |> Map.drop([:__meta__])}
    else
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp start_locked_anonymous_claim(_repo, %{status: "claimed"}, _attributes, _current_time),
    do: {:domain_error, :claimed_or_in_flight}

  defp start_locked_anonymous_claim(
         _repo,
         %{claim_attempt_token_hash: attempt},
         _attributes,
         _current_time
       )
       when not is_nil(attempt),
       do: {:domain_error, :claimed_or_in_flight}

  defp start_locked_anonymous_claim(_repo, _registration, _attributes, _current_time),
    do: {:domain_error, :claim_expired}

  defp revoke_registration_token(repo, token, registration_id, revoked_at) do
    with {:ok, _token} <-
           token |> Ecto.Changeset.change(revoked_at: revoked_at) |> repo.update(),
         :ok <-
           insert_agent_event(repo, registration_id, "token.revoked", %{
             reason: "claim_upgrade"
           }) do
      {:cont, :ok}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp revoke_provider_registration(repo, registration, issuer, subject, revoked_at, count) do
    repo.update_all(
      from(token in AccessToken,
        where: token.registration_id == ^registration.id and is_nil(token.revoked_at)
      ),
      set: [revoked_at: revoked_at]
    )

    with {:ok, _registration} <-
           registration |> Ecto.Changeset.change(status: "revoked") |> repo.update(),
         :ok <-
           insert_agent_event(repo, registration.id, "registration.revoked", %{
             issuer: issuer,
             subject: subject
           }) do
      {:cont, {:ok, count + 1}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp normalize_domain_transaction({:ok, :ok}), do: :ok
  defp normalize_domain_transaction({:ok, {:domain_error, reason}}), do: {:error, reason}
  defp normalize_domain_transaction({:error, reason}), do: {:error, reason}

  defp confirm_locked_claim(_repo, nil, _code_hash, _user_id, _at, _verified, _address, _limit),
    do: {:error, :invalid_claim_token}

  defp confirm_locked_claim(
         repo,
         %{status: "pending"} = registration,
         code_hash,
         user_id,
         claimed_at,
         email_verified,
         address,
         attempt_limit
       ) do
    if secure_digest_match?(registration.user_code_hash, code_hash) do
      claim_locked_registration(repo, registration, user_id, claimed_at, email_verified, address)
    else
      reject_claim_code(repo, registration, address, attempt_limit)
    end
  end

  defp confirm_locked_claim(
         _repo,
         %{status: "claimed"},
         _hash,
         _user,
         _at,
         _verified,
         _address,
         _limit
       ),
       do: {:error, :already_claimed}

  defp confirm_locked_claim(_repo, _registration, _hash, _user, _at, _verified, _address, _limit),
    do: {:error, :expired_token}

  defp record_locked_sign_in_failure(_repo, nil, _address, _limit),
    do: {:error, :invalid_claim_token}

  defp record_locked_sign_in_failure(repo, %{status: "pending"} = registration, address, limit) do
    failed_attempts = registration.failed_sign_in_attempts + 1
    expired? = failed_attempts >= limit

    updates =
      if expired?,
        do: %{failed_sign_in_attempts: failed_attempts, status: "expired"},
        else: %{failed_sign_in_attempts: failed_attempts}

    registration
    |> Ecto.Changeset.change(updates)
    |> repo.update()
    |> finish_sign_in_failure(repo, registration.id, address, expired?)
  end

  defp record_locked_sign_in_failure(_repo, _registration, _address, _limit),
    do: {:error, :expired_token}

  defp claim_locked_registration(repo, registration, user_id, claimed_at, email_verified, address) do
    registration
    |> Ecto.Changeset.change(%{
      status: "claimed",
      claimed_at: claimed_at,
      claimed_by_user_id: user_id,
      email_verified: email_verified,
      confirmed_address: address
    })
    |> repo.update()
    |> finish_claim(repo, registration.id, user_id, address)
  end

  defp finish_claim({:ok, _registration}, repo, registration_id, user_id, address) do
    insert_agent_event(repo, registration_id, "claim.confirmed", %{
      claimed_by_user_id: user_id,
      network_address: address
    })
  end

  defp finish_claim({:error, reason}, _repo, _id, _user_id, _address), do: {:error, reason}

  defp reject_claim_code(repo, registration, address, attempt_limit) do
    failed_attempts = registration.failed_claim_attempts + 1
    expired? = failed_attempts >= attempt_limit

    updates =
      if expired?,
        do: %{failed_claim_attempts: failed_attempts, status: "expired"},
        else: %{failed_claim_attempts: failed_attempts}

    registration
    |> Ecto.Changeset.change(updates)
    |> repo.update()
    |> finish_claim_rejection(repo, registration.id, address, expired?)
  end

  defp finish_claim_rejection({:error, reason}, _repo, _id, _address, _expired?),
    do: {:error, reason}

  defp finish_claim_rejection({:ok, _registration}, _repo, _id, _address, false),
    do: {:error, :invalid_user_code}

  defp finish_claim_rejection({:ok, _registration}, repo, id, address, true) do
    case insert_agent_event(repo, id, "registration.expired", %{
           reason: "claim_attempt_limit",
           network_address: address
         }) do
      :ok -> {:error, :expired_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_sign_in_failure({:error, reason}, _repo, _id, _address, _expired?),
    do: {:error, reason}

  defp finish_sign_in_failure({:ok, _registration}, _repo, _id, _address, false), do: :ok

  defp finish_sign_in_failure({:ok, _registration}, repo, id, address, true) do
    case insert_agent_event(repo, id, "registration.expired", %{
           reason: "sign_in_attempt_limit",
           network_address: address
         }) do
      :ok -> {:error, :expired_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp expire_registrations(repo, registrations, expired_at) do
    Enum.reduce_while(registrations, :ok, fn registration, :ok ->
      case expire_registration(repo, registration, expired_at) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp expire_registration(repo, registration, expired_at) do
    with {:ok, _registration} <-
           registration |> Ecto.Changeset.change(status: "expired") |> repo.update() do
      insert_agent_event(repo, registration.id, "registration.expired", %{
        expired_at: expired_at,
        reason: "registration_ttl"
      })
    end
  end

  defp revoke_user_tokens(repo, tokens, revoked_at) do
    Enum.reduce_while(tokens, :ok, fn token, :ok ->
      repo.update_all(
        from(access_token in AccessToken, where: access_token.token_hash == ^token.hash),
        set: [revoked_at: revoked_at]
      )

      case insert_agent_event(repo, token.registration_id, "token.revoked", %{
             reason: "user_bulk_revocation"
           }) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp revoke_registrations(repo, registrations, revoked_at) do
    Enum.reduce_while(registrations, :ok, fn registration, :ok ->
      with {:ok, _registration} <-
             registration |> Ecto.Changeset.change(status: "revoked") |> repo.update(),
           :ok <-
             insert_agent_event(repo, registration.id, "registration.revoked", %{
               reason: "user_bulk_revocation",
               revoked_at: revoked_at
             }) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp revoke_access_token(repo, hash, revoked_at) do
    token =
      repo.one(
        from(access_token in AccessToken,
          where: access_token.token_hash == ^hash,
          lock: "FOR UPDATE"
        )
      )

    case token do
      nil ->
        :ok

      %{revoked_at: revoked} when not is_nil(revoked) ->
        :ok

      token ->
        with {:ok, _token} <-
               token |> Ecto.Changeset.change(revoked_at: revoked_at) |> repo.update() do
          insert_agent_event(repo, token.registration_id, "token.revoked", %{})
        end
    end
  end

  defp find_registration(repo, attribute, value) do
    query = from(registration in Registration, where: field(registration, ^attribute) == ^value)

    case repo.one(query) do
      nil -> {:error, :not_found}
      registration -> {:ok, registration |> Map.from_struct() |> Map.drop([:__meta__])}
    end
  end

  defp insert_registration(repo, registration) do
    with {:ok, _record} <- repo.insert(struct(Registration, registration)),
         :ok <-
           insert_agent_event(repo, registration.id, "registration.created", %{
             registration_type: registration.registration_type,
             network_address: registration.registration_address,
             issuer: Map.get(registration, :provider_issuer),
             subject: Map.get(registration, :provider_subject),
             client_id: Map.get(registration, :provider_client_id)
           }),
         :ok <- maybe_record_initial_claim_events(repo, registration) do
      {:ok, registration}
    end
  end

  defp maybe_record_initial_claim_events(repo, registration) do
    if is_binary(registration.user_code_hash) do
      with :ok <-
             insert_agent_event(repo, registration.id, "claim.requested", %{
               email: registration.claim_email
             }) do
        insert_agent_event(repo, registration.id, "user_code.minted", %{})
      end
    else
      :ok
    end
  end

  defp insert_agent_event(repo, registration_id, name, metadata) do
    case repo.insert(%Event{
           registration_id: registration_id,
           name: name,
           metadata: metadata,
           created_at: System.system_time(:second)
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp acquire_registration_lock(repo) do
    case SQL.query(repo, "SELECT pg_advisory_xact_lock($1)", [@registration_lock]) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp enforce_registration_limits(repo, since, address, address_limit, global_limit) do
    with :ok <- enforce_address_registration_limit(repo, since, address, address_limit) do
      count =
        repo.aggregate(
          from(registration in Registration, where: registration.created_at >= ^since),
          :count
        )

      allow_registration_count(count, global_limit)
    end
  end

  defp enforce_address_registration_limit(_repo, _since, nil, _limit), do: :ok

  defp enforce_address_registration_limit(repo, since, address, limit) do
    count =
      repo.aggregate(
        from(registration in Registration,
          where:
            registration.created_at >= ^since and registration.registration_address == ^address
        ),
        :count
      )

    allow_registration_count(count, limit)
  end

  defp allow_registration_count(count, limit) when count < limit, do: :ok
  defp allow_registration_count(_count, _limit), do: {:error, :rate_limited}

  defp secure_digest_match?(expected, actual) do
    byte_size(expected) == byte_size(actual) and Plug.Crypto.secure_compare(expected, actual)
  end

  defp transaction(repo, callback) do
    repo.transaction(fn ->
      case callback.() do
        {:ok, value} -> {:value, value}
        :ok -> :ok
        {:error, reason} -> repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {:value, value}} -> {:ok, value}
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
