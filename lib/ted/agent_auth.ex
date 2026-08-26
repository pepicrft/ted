defmodule Ted.AgentAuth do
  @moduledoc """
  Implements the user-claimed auth.md registration and credential exchange for Ted.

  High-entropy registration secrets and access tokens are stored as
  [Secure Hash Algorithm 2](https://csrc.nist.gov/pubs/fips/180-4/upd1/final) 256-bit digests.
  Six-digit user codes use a keyed hash so a database reader cannot enumerate
  their small value space offline.
  A claim can be completed only by an authenticated Ted user whose email
  matches the registration login hint.
  """

  alias Ted.Accounts
  alias Ted.AgentAuth.ProviderVerifier
  alias Ted.Index

  @claim_grant "urn:workos:agent-auth:grant-type:claim"
  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @identity_type "urn:ietf:params:oauth:token-type:id-jag"
  @scopes ~w(profile:read profile:write objectives:read objectives:write check_ins:read check_ins:write meals:read meals:write workouts:read workouts:write plans:read plans:write mcp)
  @agent_scopes @scopes
  @pre_claim_scopes ~w(mcp)
  @signing_key_term {__MODULE__, :signing_key}

  @spec claim_grant() :: String.t()
  def claim_grant, do: @claim_grant

  @spec jwt_bearer_grant() :: String.t()
  def jwt_bearer_grant, do: @jwt_bearer_grant

  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @spec agent_scopes() :: [String.t()]
  def agent_scopes, do: @agent_scopes

  @spec pre_claim_scopes() :: [String.t()]
  def pre_claim_scopes, do: @pre_claim_scopes

  @spec identity_assertion_type() :: String.t()
  def identity_assertion_type, do: ProviderVerifier.identity_type()

  @spec revocation_event() :: String.t()
  def revocation_event, do: ProviderVerifier.revocation_event()

  @spec poll_interval(keyword()) :: pos_integer()
  def poll_interval(opts \\ []), do: option(opts, :poll_interval_seconds, 5)

  @spec claim_attempt_ttl(keyword()) :: pos_integer()
  def claim_attempt_ttl(opts \\ []), do: option(opts, :claim_attempt_ttl_seconds, 600)

  @spec create_anonymous_registration(keyword()) :: {:ok, map()} | {:error, term()}
  def create_anonymous_registration(opts \\ []) do
    current_time = now(opts)
    claim_token = secret("clm_")

    registration = %{
      id: Ecto.UUID.generate(),
      registration_type: "anonymous",
      status: "pending",
      claim_email: nil,
      claim_token_hash: digest(claim_token),
      claim_attempt_token_hash: nil,
      user_code_hash: nil,
      created_at: current_time,
      expires_at: current_time + option(opts, :registration_ttl_seconds, 86_400),
      claim_attempt_expires_at: nil,
      registration_address: option(opts, :network_address, nil),
      claimed_by_user_id: nil,
      email_verified: false
    }

    with {:ok, _registration} <- put_registration(registration, current_time, opts),
         {:ok, assertion, assertion_expires} <- sign_assertion(registration, opts),
         :ok <-
           Index.agent_auth(
             index(opts),
             {:record_event, registration.id, "assertion.issued", %{}}
           ) do
      {:ok,
       %{
         registration: registration,
         claim_token: claim_token,
         identity_assertion: assertion,
         assertion_expires: assertion_expires
       }}
    end
  end

  @spec start_anonymous_claim(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def start_anonymous_claim(claim_token, email, opts \\ [])

  def start_anonymous_claim(claim_token, email, opts)
      when is_binary(claim_token) and is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    current_time = now(opts)
    attempt_token = secret("cla_")
    user_code = user_code()

    with :ok <- validate_email(email),
         {:ok, registration} <-
           Index.agent_auth(index(opts), {:registration_by_claim_token, digest(claim_token)}),
         {:ok, updated} <-
           Index.agent_auth(
             index(opts),
             {:start_anonymous_claim, registration.id,
              %{
                claim_email: email,
                claim_attempt_token_hash: digest(attempt_token),
                user_code_hash: user_code_digest(user_code, opts),
                claim_attempt_expires_at: current_time + claim_attempt_ttl(opts)
              }, current_time}
           ) do
      {:ok,
       %{
         registration: updated,
         claim_attempt_token: attempt_token,
         user_code: user_code
       }}
    else
      {:error, :not_found} -> {:error, :invalid_claim_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def start_anonymous_claim(_claim_token, _email, _opts), do: {:error, :invalid_request}

  @spec create_identity_registration(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:interaction_required, map()} | {:error, term()}
  def create_identity_registration(assertion_type, assertion, opts \\ [])

  def create_identity_registration(assertion_type, assertion, opts)
      when assertion_type == @identity_type and is_binary(assertion) do
    verifier_opts = provider_verifier_opts(opts)

    with {:ok, claims} <- ProviderVerifier.verify_identity(assertion, issuer(opts), verifier_opts),
         :ok <-
           Index.agent_auth(
             index(opts),
             {:provider_assertion_seen, claims["iss"], claims["jti"]}
           ) do
      register_provider_identity(claims, opts)
    end
  end

  def create_identity_registration(_assertion_type, _assertion, _opts),
    do: {:error, :invalid_request}

  @spec process_security_event(String.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def process_security_event(token, opts \\ []) when is_binary(token) do
    with {:ok, claims} <-
           ProviderVerifier.verify_event(token, issuer(opts), provider_verifier_opts(opts)) do
      Index.agent_auth(
        index(opts),
        {:revoke_provider_identity, claims["iss"], claims["sub"], now(opts)}
      )
    end
  end

  @spec create_service_registration(String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_service_registration(email, opts \\ [])

  def create_service_registration(email, opts) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    current_time = now(opts)
    address = option(opts, :network_address, nil)

    with :ok <- validate_email(email) do
      create_registration(email, address, current_time, opts)
    end
  end

  def create_service_registration(_email, _opts), do: {:error, :invalid_request}

  @spec get_claim_attempt(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_claim_attempt(claim_attempt_token, opts \\ [])

  def get_claim_attempt(claim_attempt_token, opts) when is_binary(claim_attempt_token) do
    with {:ok, registration} <-
           Index.agent_auth(
             index(opts),
             {:registration_by_claim_attempt, digest(claim_attempt_token)}
           ),
         :ok <- ensure_current(registration, now(opts), opts),
         :ok <- ensure_claim_attempt_current(registration, now(opts)) do
      {:ok, registration}
    else
      {:error, :not_found} -> {:error, :invalid_claim_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_claim_attempt(_claim_attempt_token, _opts), do: {:error, :invalid_claim_token}

  @spec record_claim_visit(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def record_claim_visit(claim_attempt_token, opts \\ []) do
    with {:ok, registration} <- get_claim_attempt(claim_attempt_token, opts),
         :ok <-
           Index.agent_auth(
             index(opts),
             {:record_claim_address, registration.id, option(opts, :network_address, nil)}
           ) do
      {:ok, registration}
    end
  end

  @spec record_sign_in_failure(String.t(), keyword()) :: :ok | {:error, term()}
  def record_sign_in_failure(claim_attempt_token, opts \\ []) do
    with {:ok, registration} <- get_claim_attempt(claim_attempt_token, opts) do
      Index.agent_auth(
        index(opts),
        {:record_sign_in_failure, registration.id, option(opts, :network_address, nil),
         option(opts, :sign_in_attempt_limit, 10)}
      )
    end
  end

  @spec confirm_claim(String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def confirm_claim(claim_attempt_token, user_code, user, opts \\ [])

  def confirm_claim(
        claim_attempt_token,
        user_code,
        %{id: user_id, email: email, email_verified_at: email_verified_at},
        opts
      )
      when is_binary(claim_attempt_token) and is_binary(user_code) and is_binary(user_id) and
             is_binary(email) do
    current_time = now(opts)

    with {:ok, registration} <- get_claim_attempt(claim_attempt_token, opts),
         :ok <- ensure_pending(registration),
         :ok <- ensure_same_user(registration, email),
         :ok <- ensure_verified_email(email_verified_at),
         :ok <-
           Index.agent_auth(
             index(opts),
             {:confirm_claim, registration.id, user_code_digest(user_code, opts), user_id,
              current_time, true, option(opts, :network_address, nil),
              option(opts, :claim_attempt_limit, 5)}
           ) do
      {:ok,
       Map.merge(registration, %{
         status: "claimed",
         claimed_at: current_time,
         claimed_by_user_id: user_id
       })}
    end
  end

  def confirm_claim(_claim_attempt_token, _user_code, _user, _opts),
    do: {:error, :invalid_request}

  @spec exchange_claim(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def exchange_claim(claim_token, opts \\ [])

  def exchange_claim(claim_token, opts) when is_binary(claim_token) do
    current_time = now(opts)

    with {:ok, registration} <-
           Index.agent_auth(index(opts), {:registration_by_claim_token, digest(claim_token)}),
         :ok <- ensure_current(registration, current_time, opts) do
      exchange_registration_claim(registration, current_time, opts)
    else
      {:error, :not_found} -> {:error, :expired_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def exchange_claim(_claim_token, _opts), do: {:error, :invalid_request}

  @spec exchange_assertion(String.t(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def exchange_assertion(assertion, resource \\ nil, opts \\ [])

  def exchange_assertion(assertion, resource, opts) when is_binary(assertion) do
    with {:ok, claims} <- verify_assertion(assertion, opts),
         :ok <- validate_resource(resource, opts),
         {:ok, registration} <-
           Index.agent_auth(index(opts), {:registration_by_id, claims["sub"]}),
         :ok <- validate_registration_assertion(registration, claims),
         {:ok, token} <-
           issue_access_token(
             registration,
             normalized_resource(resource, opts),
             scopes_for(registration),
             opts
           ) do
      {:ok, token_response(token, opts)}
    else
      _error -> {:error, :invalid_grant}
    end
  end

  def exchange_assertion(_assertion, _resource, _opts), do: {:error, :invalid_request}

  @spec authorize(String.t(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def authorize(token, required_scopes, opts \\ [])

  def authorize(token, required_scopes, opts)
      when is_binary(token) and is_list(required_scopes) do
    authorize_access_token(token, required_scopes, opts)
  end

  def authorize(_token, _required_scopes, _opts), do: {:error, :invalid_token}

  @spec revoke_access_token(String.t(), keyword()) :: :ok | {:error, term()}
  def revoke_access_token(token, opts \\ [])

  def revoke_access_token(token, opts) when is_binary(token) do
    Index.agent_auth(index(opts), {:revoke_access_token, digest(token), now(opts)})
  end

  def revoke_access_token(_token, _opts), do: {:error, :invalid_token}

  @spec revoke_user_access_tokens(String.t(), keyword()) :: {:ok, non_neg_integer()}
  def revoke_user_access_tokens(user_id, opts \\ []) when is_binary(user_id) do
    Index.agent_auth(index(opts), {:revoke_user_access_tokens, user_id, now(opts)})
  end

  @spec jwks(keyword()) :: {:ok, map()} | {:error, term()}
  def jwks(opts \\ []) do
    with {:ok, key} <- signing_key(opts),
         {:ok, signing_key_id} <- key_id(opts) do
      {_, public_key} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

      {:ok,
       %{
         keys: [
           public_key
           |> Map.put("alg", "RS256")
           |> Map.put("kid", signing_key_id)
           |> Map.put("use", "sig")
         ]
       }}
    end
  end

  defp register_provider_identity(claims, opts) do
    repo = index(opts)

    case Index.agent_auth(
           repo,
           {:claimed_registration_by_provider, claims["iss"], claims["sub"]}
         ) do
      {:ok, registration} ->
        with {:ok, user} <- Accounts.get_user(registration.claimed_by_user_id, repo) do
          create_claimed_provider_registration(user, claims, opts)
        end

      {:error, :not_found} ->
        register_first_provider_identity(claims, opts)
    end
  end

  defp register_first_provider_identity(claims, opts) do
    repo = index(opts)
    email = claims["email"] |> String.trim() |> String.downcase()

    case Accounts.get_user_by_email(email, repo) do
      {:ok, _existing_user} ->
        current_time = now(opts)

        case create_registration(
               email,
               option(opts, :network_address, nil),
               current_time,
               opts,
               provider_attributes(claims)
             ) do
          {:ok, result} -> {:interaction_required, result}
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        name = provider_name(claims)

        with {:ok, user} <-
               Accounts.create_verified_agent_user(%{"email" => email, "name" => name}, repo) do
          create_claimed_provider_registration(user, claims, opts)
        end
    end
  end

  defp create_claimed_provider_registration(user, claims, opts) do
    current_time = now(opts)

    registration =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          registration_type: "identity_assertion",
          status: "claimed",
          claim_email: user.email,
          claim_token_hash: digest(secret("unused_")),
          claim_attempt_token_hash: nil,
          user_code_hash: nil,
          created_at: current_time,
          expires_at: current_time + option(opts, :registration_ttl_seconds, 86_400),
          claim_attempt_expires_at: nil,
          claimed_at: current_time,
          claimed_by_user_id: user.id,
          registration_address: option(opts, :network_address, nil),
          email_verified: true
        },
        provider_attributes(claims)
      )

    with {:ok, _registration} <- put_registration(registration, current_time, opts),
         {:ok, assertion, assertion_expires} <- sign_assertion(registration, opts),
         :ok <-
           Index.agent_auth(
             index(opts),
             {:record_event, registration.id, "assertion.issued", %{}}
           ) do
      {:ok,
       %{
         registration: registration,
         identity_assertion: assertion,
         assertion_expires: assertion_expires
       }}
    end
  end

  defp provider_attributes(claims) do
    %{
      registration_type: "identity_assertion",
      provider_issuer: claims["iss"],
      provider_subject: claims["sub"],
      provider_client_id: claims["client_id"],
      provider_jti: claims["jti"]
    }
  end

  defp provider_name(claims) do
    case claims["name"] do
      name when is_binary(name) and byte_size(name) > 0 -> name
      _name -> claims["email"] |> String.split("@") |> hd()
    end
  end

  defp create_registration(email, address, current_time, opts, extra_attributes \\ %{}) do
    claim_token = secret("clm_")
    claim_attempt_token = secret("cla_")
    user_code = user_code()

    registration =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          registration_type: "service_auth",
          status: "pending",
          claim_email: email,
          claim_token_hash: digest(claim_token),
          claim_attempt_token_hash: digest(claim_attempt_token),
          user_code_hash: user_code_digest(user_code, opts),
          created_at: current_time,
          expires_at: current_time + option(opts, :registration_ttl_seconds, 86_400),
          claim_attempt_expires_at: current_time + claim_attempt_ttl(opts),
          registration_address: address
        },
        extra_attributes
      )

    with {:ok, _registration} <- put_registration(registration, current_time, opts) do
      {:ok,
       %{
         registration: registration,
         claim_token: claim_token,
         claim_attempt_token: claim_attempt_token,
         user_code: user_code
       }}
    end
  end

  defp put_registration(registration, current_time, opts) do
    operation =
      {:create_rate_limited_registration, registration, current_time - 3_600,
       option(opts, :registration_address_limit, 10),
       option(opts, :registration_global_limit, 100)}

    Index.agent_auth(index(opts), operation)
  end

  defp exchange_registration_claim(%{status: "claimed"} = registration, _now, opts),
    do: issue_response(registration, opts)

  defp exchange_registration_claim(%{status: "pending"} = registration, current_time, opts) do
    cond do
      is_nil(registration.claim_attempt_expires_at) ->
        {:error, :authorization_pending}

      registration.claim_attempt_expires_at <= current_time ->
        {:error, :expired_token}

      polled_too_quickly?(registration, current_time, opts) ->
        {:error, :slow_down}

      true ->
        with :ok <-
               Index.agent_auth(index(opts), {:mark_polled, registration.id, current_time}) do
          {:error, :authorization_pending}
        end
    end
  end

  defp exchange_registration_claim(_registration, _now, _opts), do: {:error, :invalid_grant}

  defp issue_response(registration, opts) do
    with {:ok, assertion, assertion_expires} <- sign_assertion(registration, opts),
         :ok <- revoke_pre_claim_tokens(registration, opts),
         {:ok, token} <-
           issue_access_token(registration, issuer(opts), scopes_for(registration), opts),
         :ok <-
           Index.agent_auth(
             index(opts),
             {:record_event, registration.id, "assertion.issued", %{}}
           ) do
      {:ok,
       token
       |> token_response(opts)
       |> Map.merge(%{
         identity_assertion: assertion,
         assertion_expires: assertion_expires
       })}
    end
  end

  defp issue_access_token(registration, resource, scopes, opts) do
    value = secret("mat_")
    issued_at = now(opts)

    token = %{
      value: value,
      token_hash: digest(value),
      registration_id: registration.id,
      scopes: Enum.join(scopes, " "),
      resource: resource,
      created_at: issued_at,
      expires_at: issued_at + option(opts, :access_token_ttl_seconds, 3_600)
    }

    with :ok <- Index.agent_auth(index(opts), {:put_access_token, token}) do
      {:ok, token}
    end
  end

  defp token_response(token, opts) do
    %{
      access_token: token.value,
      token_type: "Bearer",
      expires_in: max(token.expires_at - now(opts), 0),
      scope: token.scopes
    }
  end

  defp authorize_access_token(token, required_scopes, opts) do
    with {:ok, access_token} <-
           Index.agent_auth(index(opts), {:access_token, digest(token)}),
         true <- is_nil(access_token.revoked_at),
         true <- access_token.expires_at > now(opts),
         true <- authorized_registration?(access_token),
         :ok <- authorize_resource(access_token.resource, option(opts, :resource, nil)),
         :ok <- authorize_scopes(access_token.scopes, required_scopes) do
      {:ok, Map.put(access_token, :kind, :access_token)}
    else
      {:error, :insufficient_scope} -> {:error, :insufficient_scope}
      _error -> {:error, :invalid_token}
    end
  end

  defp authorized_registration?(%{registration_status: "claimed"}), do: true

  defp authorized_registration?(%{
         registration_status: "pending",
         registration_type: "anonymous",
         scopes: scopes
       }),
       do: String.split(scopes) == @pre_claim_scopes

  defp authorized_registration?(_access_token), do: false

  defp validate_registration_assertion(
         %{status: "claimed"} = registration,
         claims
       ) do
    if registration.claim_email == claims["email"] and
         registration.claimed_by_user_id == claims["user_id"] and registration.email_verified and
         claims["email_verified"] == true,
       do: :ok,
       else: {:error, :invalid_grant}
  end

  defp validate_registration_assertion(
         %{status: "pending", registration_type: "anonymous", claimed_by_user_id: nil},
         claims
       ) do
    if claims["user_id"] in [nil, :null] and
         claims["scope"] == Enum.join(@pre_claim_scopes, " "),
       do: :ok,
       else: {:error, :invalid_grant}
  end

  defp validate_registration_assertion(_registration, _claims),
    do: {:error, :invalid_grant}

  defp scopes_for(%{status: "pending", registration_type: "anonymous"}),
    do: @pre_claim_scopes

  defp scopes_for(_registration), do: @agent_scopes

  defp revoke_pre_claim_tokens(
         %{registration_type: "anonymous", status: "claimed"} = registration,
         opts
       ) do
    Index.agent_auth(
      index(opts),
      {:revoke_registration_access_tokens, registration.id, now(opts)}
    )
  end

  defp revoke_pre_claim_tokens(_registration, _opts), do: :ok

  defp authorize_scopes(scopes, required_scopes) do
    granted = scopes |> String.split() |> MapSet.new()

    if Enum.all?(required_scopes, &MapSet.member?(granted, &1)),
      do: :ok,
      else: {:error, :insufficient_scope}
  end

  defp authorize_resource(_granted, nil), do: :ok
  defp authorize_resource(granted, requested) when granted == requested, do: :ok
  defp authorize_resource(_granted, _requested), do: {:error, :invalid_token}

  defp sign_assertion(registration, opts) do
    with {:ok, key} <- signing_key(opts),
         {:ok, signing_key_id} <- key_id(opts) do
      issued_at = now(opts)
      expires_at = issued_at + option(opts, :assertion_ttl_seconds, 86_400)

      claims = %{
        "iss" => issuer(opts),
        "sub" => registration.id,
        "aud" => issuer(opts),
        "iat" => issued_at,
        "exp" => expires_at,
        "jti" => secret("jti_"),
        "user_id" => registration.claimed_by_user_id,
        "email" => registration.claim_email,
        "email_verified" => registration.email_verified,
        "scope" => Enum.join(scopes_for(registration), " ")
      }

      header = %{
        "alg" => "RS256",
        "kid" => signing_key_id,
        "typ" => "oauth-id-jag+jwt"
      }

      {_, assertion} = key |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()

      with {:ok, expiration} <- DateTime.from_unix(expires_at) do
        {:ok, assertion, DateTime.to_iso8601(expiration)}
      end
    end
  end

  defp verify_assertion(assertion, opts) do
    with {:ok, key} <- signing_key(opts),
         {:ok, signing_key_id} <- key_id(opts),
         %JOSE.JWS{fields: %{"typ" => "oauth-id-jag+jwt", "kid" => key_id}} <-
           JOSE.JWT.peek_protected(assertion),
         true <- key_id == signing_key_id,
         {true, %JOSE.JWT{fields: claims}, _signature} <-
           key |> JOSE.JWK.to_public() |> JOSE.JWT.verify_strict(["RS256"], assertion),
         :ok <- validate_assertion_claims(claims, opts) do
      {:ok, claims}
    else
      _error -> {:error, :invalid_grant}
    end
  end

  defp validate_assertion_claims(claims, opts) do
    current_time = now(opts)

    with true <- valid_assertion_issuer?(claims, opts),
         true <- valid_assertion_times?(claims, current_time),
         true <- valid_assertion_subject?(claims) do
      :ok
    else
      false -> {:error, :invalid_grant}
    end
  end

  defp valid_assertion_issuer?(claims, opts) do
    claims["iss"] == issuer(opts) and claims["aud"] == issuer(opts)
  end

  defp valid_assertion_times?(claims, current_time) do
    is_integer(claims["iat"]) and claims["iat"] <= current_time + 60 and
      is_integer(claims["exp"]) and claims["exp"] > current_time
  end

  defp valid_assertion_subject?(claims) do
    is_binary(claims["sub"]) and is_binary(claims["scope"])
  end

  defp signing_key(opts) do
    cond do
      private_key = option(opts, :private_key_pem, nil) ->
        {:ok, JOSE.JWK.from_pem(private_key)}

      option(opts, :allow_ephemeral_signing_key, true) ->
        {:ok, ephemeral_signing_key()}

      true ->
        {:error, :signing_key_unavailable}
    end
  rescue
    _error -> {:error, :signing_key_unavailable}
  end

  defp ephemeral_signing_key do
    case :persistent_term.get(@signing_key_term, nil) do
      %JOSE.JWK{} = key -> key
      nil -> initialize_ephemeral_signing_key()
    end
  end

  defp initialize_ephemeral_signing_key do
    :global.trans({@signing_key_term, self()}, fn ->
      case :persistent_term.get(@signing_key_term, nil) do
        %JOSE.JWK{} = key ->
          key

        nil ->
          key = JOSE.JWK.generate_key({:rsa, 2_048})
          :persistent_term.put(@signing_key_term, key)
          key
      end
    end)
  end

  defp key_id(opts) do
    with {:ok, key} <- signing_key(opts),
         {_, public_key} <- key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map() do
      encoded_key = JSON.encode!(public_key)
      {:ok, encoded_key |> digest() |> Base.url_encode64(padding: false) |> binary_part(0, 16)}
    end
  end

  defp ensure_current(%{status: "expired"}, _current_time, _opts), do: {:error, :expired_token}

  defp ensure_current(%{expires_at: expires_at}, current_time, _opts)
       when expires_at > current_time,
       do: :ok

  defp ensure_current(%{id: id, status: "pending"}, current_time, opts) do
    Index.agent_auth(index(opts), {:expire_registration, id, current_time})
    {:error, :expired_token}
  end

  defp ensure_current(_registration, _current_time, _opts), do: {:error, :expired_token}

  defp ensure_claim_attempt_current(%{status: "claimed"}, _current_time), do: :ok

  defp ensure_claim_attempt_current(%{claim_attempt_expires_at: expires_at}, current_time)
       when expires_at > current_time,
       do: :ok

  defp ensure_claim_attempt_current(_registration, _current_time),
    do: {:error, :expired_token}

  defp ensure_pending(%{status: "pending"}), do: :ok
  defp ensure_pending(%{status: "claimed"}), do: {:error, :already_claimed}
  defp ensure_pending(_registration), do: {:error, :expired_token}

  defp ensure_same_user(%{claim_email: expected}, email) do
    if expected == String.downcase(email), do: :ok, else: {:error, :account_mismatch}
  end

  defp ensure_verified_email(%DateTime{}), do: :ok
  defp ensure_verified_email(_email_verified_at), do: {:error, :email_not_verified}

  defp polled_too_quickly?(%{last_polled_at: nil}, _now, _opts), do: false

  defp polled_too_quickly?(registration, current_time, opts),
    do: current_time - registration.last_polled_at < poll_interval(opts)

  defp validate_email(email) do
    if byte_size(email) <= 254 and Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email),
      do: :ok,
      else: {:error, :invalid_login_hint}
  end

  defp normalize_user_code(code), do: String.trim(code)

  defp validate_resource(resource, _opts) when resource in [nil, ""], do: :ok

  defp validate_resource(resource, opts) do
    if resource in [issuer(opts), issuer(opts) <> "/mcp"],
      do: :ok,
      else: {:error, :invalid_target}
  end

  defp normalized_resource(resource, opts) when resource in [nil, ""], do: issuer(opts)
  defp normalized_resource(resource, _opts), do: resource

  defp config, do: Application.get_env(:ted, :agent_auth, [])

  defp provider_verifier_opts(opts) do
    [
      trusted_providers: option(opts, :trusted_providers, []),
      jwks_client: option(opts, :jwks_client, Ted.AgentAuth.JwksClient),
      jwks_document: Keyword.get(opts, :jwks_document),
      finch: option(opts, :finch, Ted.Finch),
      maximum_auth_age_seconds: option(opts, :maximum_auth_age_seconds, 3_600),
      now: now(opts)
    ]
  end

  defp index(opts), do: Keyword.get_lazy(opts, :index, &Index.context/0)
  defp issuer(opts), do: Keyword.get_lazy(opts, :issuer, &TedWeb.Endpoint.url/0)
  defp now(opts), do: Keyword.get(opts, :now, System.system_time(:second))
  defp option(opts, key, default), do: Keyword.get(opts, key, Keyword.get(config(), key, default))
  defp digest(value), do: :crypto.hash(:sha256, value)

  defp user_code_digest(code, opts) do
    key = option(opts, :user_code_hmac_key, nil)

    :crypto.mac(:hmac, :sha256, key, "ted:agent-user-code:v1:" <> normalize_user_code(code))
  end

  defp secret(prefix),
    do: prefix <> (:crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false))

  defp user_code do
    4
    |> :crypto.strong_rand_bytes()
    |> :binary.decode_unsigned()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end
end
