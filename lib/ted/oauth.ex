defmodule Ted.OAuth do
  @moduledoc "Manages public [OAuth 2.0](https://www.rfc-editor.org/rfc/rfc6749) clients and user-authorized credentials."

  import Ecto.Query

  alias Ted.AgentAuth
  alias Ted.OAuth.{AccessToken, AuthorizationCode, Client, RefreshToken}
  alias Ted.Repo

  @authorization_code_grant "authorization_code"
  @refresh_token_grant "refresh_token"
  @supported_grants [@authorization_code_grant, @refresh_token_grant]
  @authorization_code_ttl_seconds 300
  @access_token_ttl_seconds 3_600
  @refresh_token_ttl_seconds 2_592_000
  @maximum_state_length 1_024

  @type authorization_request :: %{
          client: map(),
          redirect_uri: String.t(),
          code_challenge: String.t(),
          scopes: [String.t()],
          resource: String.t(),
          state: String.t() | nil
        }

  @spec supported_grants() :: [String.t()]
  def supported_grants, do: @supported_grants

  @spec register_client(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def register_client(params, opts \\ [])

  def register_client(params, opts) when is_map(params) do
    with {:ok, redirect_uris} <- redirect_uris(params["redirect_uris"]),
         {:ok, grant_types} <- grant_types(params["grant_types"]),
         :ok <- response_types(params["response_types"]),
         :ok <- token_endpoint_auth_method(params["token_endpoint_auth_method"]),
         {:ok, name} <- client_name(params["client_name"]),
         {:ok, client} <-
           repo(opts).insert(%Client{
             name: name,
             redirect_uris: redirect_uris,
             grant_types: grant_types,
             created_at: now(opts)
           }) do
      {:ok, client_response(client)}
    else
      {:error, _reason} = error -> error
    end
  end

  def register_client(_params, _opts), do: {:error, :invalid_client_metadata}

  @spec authorization_request(map(), keyword()) ::
          {:ok, authorization_request()} | {:error, atom()}
  def authorization_request(params, opts \\ [])

  def authorization_request(params, opts) when is_map(params) do
    issuer = Keyword.fetch!(opts, :issuer)

    with :ok <- response_type(params["response_type"]),
         {:ok, client} <- client(params["client_id"], opts),
         {:ok, redirect_uri} <- registered_redirect_uri(client, params["redirect_uri"]),
         {:ok, code_challenge} <- code_challenge(params),
         {:ok, scopes} <- requested_scopes(params["scope"]),
         {:ok, resource} <- resource(params["resource"], issuer),
         {:ok, state} <- state(params["state"]) do
      {:ok,
       %{
         client: client,
         redirect_uri: redirect_uri,
         code_challenge: code_challenge,
         scopes: scopes,
         resource: resource,
         state: state
       }}
    end
  end

  def authorization_request(_params, _opts), do: {:error, :invalid_request}

  @spec issue_authorization_code(authorization_request(), Ecto.UUID.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def issue_authorization_code(request, user_id, opts \\ [])

  def issue_authorization_code(%{client: %{id: client_id}} = request, user_id, opts)
      when is_binary(user_id) do
    value = secret("toc_")

    %AuthorizationCode{
      code_hash: digest(value),
      client_id: client_id,
      user_id: user_id,
      grant_id: Ecto.UUID.generate(),
      redirect_uri: request.redirect_uri,
      code_challenge: request.code_challenge,
      scopes: Enum.join(request.scopes, " "),
      resource: request.resource,
      expires_at: now(opts) + @authorization_code_ttl_seconds
    }
    |> repo(opts).insert()
    |> case do
      {:ok, _code} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  def issue_authorization_code(_request, _user_id, _opts), do: {:error, :invalid_request}

  @spec exchange_authorization_code(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def exchange_authorization_code(params, opts \\ [])

  def exchange_authorization_code(params, opts) when is_map(params) do
    with {:ok, client_id} <- binary_parameter(params, "client_id"),
         {:ok, code} <- binary_parameter(params, "code"),
         {:ok, redirect_uri} <- binary_parameter(params, "redirect_uri"),
         {:ok, verifier} <- code_verifier(params["code_verifier"]),
         {:ok, resource} <- resource(params["resource"], Keyword.fetch!(opts, :issuer)) do
      consume_authorization_code(client_id, code, redirect_uri, verifier, resource, opts)
    end
  end

  def exchange_authorization_code(_params, _opts), do: {:error, :invalid_grant}

  @spec refresh(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def refresh(params, opts \\ [])

  def refresh(params, opts) when is_map(params) do
    with {:ok, client_id} <- binary_parameter(params, "client_id"),
         {:ok, value} <- binary_parameter(params, "refresh_token"),
         {:ok, resource} <- resource(params["resource"], Keyword.fetch!(opts, :issuer)) do
      rotate_refresh_token(client_id, value, resource, opts)
    end
  end

  def refresh(_params, _opts), do: {:error, :invalid_grant}

  @spec authorize(String.t(), [String.t()], keyword()) :: {:ok, map()} | {:error, atom()}
  def authorize(value, required_scopes, opts \\ [])

  def authorize(value, required_scopes, opts)
      when is_binary(value) and is_list(required_scopes) do
    with {:ok, token} <- access_token(value, opts),
         :ok <- active?(token, now(opts)),
         :ok <- resource_matches?(token.resource, Keyword.get(opts, :resource)),
         :ok <- required_scopes?(token.scopes, required_scopes) do
      {:ok, %{user_id: token.user_id, scopes: String.split(token.scopes)}}
    end
  end

  def authorize(_value, _required_scopes, _opts), do: {:error, :invalid_token}

  @spec revoke(String.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  def revoke(value, client_id, opts \\ [])

  def revoke(value, client_id, opts) when is_binary(value) do
    repo = repo(opts)
    timestamp = now(opts)
    hash = digest(value)

    repo.transaction(fn ->
      revoke_access_token(repo, hash, client_id, timestamp)
      revoke_refresh_token(repo, hash, client_id, timestamp)
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def revoke(_value, _client_id, _opts), do: :ok

  @spec authorization_redirect(authorization_request(), String.t(), String.t()) :: String.t()
  def authorization_redirect(request, code, issuer) do
    params = %{"code" => code, "iss" => issuer}

    params =
      if is_binary(request.state), do: Map.put(params, "state", request.state), else: params

    append_query(request.redirect_uri, params)
  end

  defp consume_authorization_code(client_id, value, redirect_uri, verifier, resource, opts) do
    repo = repo(opts)
    timestamp = now(opts)

    repo.transaction(fn ->
      code =
        repo.one(
          from(code in AuthorizationCode,
            where: code.code_hash == ^digest(value),
            lock: "FOR UPDATE"
          )
        )

      case code do
        %AuthorizationCode{consumed_at: consumed_at} = code when is_integer(consumed_at) ->
          revoke_grant_family(repo, code.grant_id, timestamp)
          {:error, :invalid_grant}

        %AuthorizationCode{} = code ->
          consume_fresh_authorization_code(
            repo,
            code,
            client_id,
            redirect_uri,
            verifier,
            resource,
            timestamp
          )

        _missing ->
          repo.rollback(:invalid_grant)
      end
    end)
    |> transaction_response()
  end

  defp rotate_refresh_token(client_id, value, resource, opts) do
    repo = repo(opts)
    timestamp = now(opts)

    repo.transaction(fn ->
      token =
        repo.one(
          from(token in RefreshToken,
            where: token.token_hash == ^digest(value),
            lock: "FOR UPDATE"
          )
        )

      case token do
        %RefreshToken{revoked_at: revoked_at} = token when is_integer(revoked_at) ->
          revoke_grant_family(repo, token.grant_id, timestamp)
          {:error, :invalid_grant}

        %RefreshToken{} = token ->
          rotate_fresh_refresh_token(repo, token, client_id, resource, timestamp)

        _missing ->
          repo.rollback(:invalid_grant)
      end
    end)
    |> transaction_response()
  end

  defp consume_fresh_authorization_code(
         repo,
         code,
         client_id,
         redirect_uri,
         verifier,
         resource,
         timestamp
       ) do
    with :ok <-
           usable_authorization_code?(
             code,
             client_id,
             redirect_uri,
             verifier,
             resource,
             timestamp
           ),
         :ok <- authorization_code_grant_enabled?(repo, code.client_id),
         {:ok, response} <- issue_credentials(repo, code, timestamp),
         {:ok, _code} <- code |> Ecto.Changeset.change(consumed_at: timestamp) |> repo.update() do
      {:ok, response}
    else
      _invalid -> repo.rollback(:invalid_grant)
    end
  end

  defp rotate_fresh_refresh_token(repo, token, client_id, resource, timestamp) do
    with :ok <- usable_refresh_token?(token, client_id, resource, timestamp),
         :ok <- refresh_token_grant_enabled?(repo, token.client_id),
         {:ok, response} <- issue_credentials(repo, token, timestamp),
         {:ok, _token} <- token |> Ecto.Changeset.change(revoked_at: timestamp) |> repo.update() do
      {:ok, response}
    else
      _invalid -> repo.rollback(:invalid_grant)
    end
  end

  defp issue_credentials(
         repo,
         %{
           client_id: client_id,
           user_id: user_id,
           grant_id: grant_id,
           scopes: scopes,
           resource: resource
         },
         timestamp
       ) do
    access_token = secret("toa_")

    with %Client{} = client <- repo.get(Client, client_id),
         {:ok, _access} <-
           repo.insert(%AccessToken{
             token_hash: digest(access_token),
             client_id: client_id,
             user_id: user_id,
             grant_id: grant_id,
             scopes: scopes,
             resource: resource,
             created_at: timestamp,
             expires_at: timestamp + @access_token_ttl_seconds
           }) do
      issue_refresh_credentials(
        repo,
        client,
        %{user_id: user_id, grant_id: grant_id, scopes: scopes, resource: resource},
        access_token,
        timestamp
      )
    else
      nil -> {:error, :invalid_grant}
      {:error, _reason} = error -> error
    end
  end

  defp issue_refresh_credentials(repo, client, grant, access_token, timestamp) do
    response = %{
      access_token: access_token,
      token_type: "Bearer",
      expires_in: @access_token_ttl_seconds,
      scope: grant.scopes
    }

    if @refresh_token_grant in client.grant_types do
      refresh_token = secret("tor_")

      with {:ok, _refresh} <-
             repo.insert(%RefreshToken{
               token_hash: digest(refresh_token),
               client_id: client.id,
               user_id: grant.user_id,
               grant_id: grant.grant_id,
               scopes: grant.scopes,
               resource: grant.resource,
               created_at: timestamp,
               expires_at: timestamp + @refresh_token_ttl_seconds
             }) do
        {:ok, Map.put(response, :refresh_token, refresh_token)}
      end
    else
      {:ok, response}
    end
  end

  defp access_token(value, opts) do
    case repo(opts).one(from(token in AccessToken, where: token.token_hash == ^digest(value))) do
      nil -> {:error, :invalid_token}
      token -> {:ok, token}
    end
  end

  defp client(client_id, opts) when is_binary(client_id) do
    case repo(opts).get(Client, client_id) do
      nil -> {:error, :invalid_client}
      client -> {:ok, Map.from_struct(client)}
    end
  end

  defp client(_client_id, _opts), do: {:error, :invalid_client}

  defp redirect_uris(uris) when is_list(uris) and uris != [] do
    uris
    |> Enum.reduce_while({:ok, []}, fn uri, {:ok, accepted} ->
      case redirect_uri(uri) do
        {:ok, value} -> {:cont, {:ok, [value | accepted]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, values |> Enum.reverse() |> Enum.uniq()}
      {:error, _reason} = error -> error
    end
  end

  defp redirect_uris(_uris), do: {:error, :invalid_redirect_uri}

  defp redirect_uri(uri) when is_binary(uri) and byte_size(uri) <= 2_000 do
    parsed = URI.parse(uri)

    cond do
      parsed.fragment != nil -> {:error, :invalid_redirect_uri}
      parsed.scheme == "https" and is_binary(parsed.host) and parsed.host != "" -> {:ok, uri}
      parsed.scheme == "http" and loopback_host?(parsed.host) -> {:ok, uri}
      true -> {:error, :invalid_redirect_uri}
    end
  end

  defp redirect_uri(_uri), do: {:error, :invalid_redirect_uri}

  defp loopback_host?(host) when host in ["localhost", "127.0.0.1", "::1"], do: true
  defp loopback_host?(_host), do: false

  defp grant_types(nil), do: {:ok, @supported_grants}

  defp grant_types(grants) when is_list(grants) and grants != [] do
    if Enum.all?(grants, &(&1 in @supported_grants)) and @authorization_code_grant in grants do
      {:ok, grants |> Enum.uniq()}
    else
      {:error, :invalid_client_metadata}
    end
  end

  defp grant_types(_grants), do: {:error, :invalid_client_metadata}

  defp response_types(nil), do: :ok
  defp response_types(["code"]), do: :ok
  defp response_types(_types), do: {:error, :invalid_client_metadata}

  defp token_endpoint_auth_method(nil), do: :ok
  defp token_endpoint_auth_method("none"), do: :ok
  defp token_endpoint_auth_method(_method), do: {:error, :invalid_client_metadata}

  defp client_name(nil), do: {:ok, "Ted client"}

  defp client_name(name) when is_binary(name) do
    name = String.trim(name)

    if name != "" and String.length(name) <= 160,
      do: {:ok, name},
      else: {:error, :invalid_client_metadata}
  end

  defp client_name(_name), do: {:error, :invalid_client_metadata}

  defp client_response(client) do
    %{
      client_id: client.id,
      client_id_issued_at: client.created_at,
      client_name: client.name,
      redirect_uris: client.redirect_uris,
      grant_types: client.grant_types,
      response_types: ["code"],
      token_endpoint_auth_method: "none"
    }
  end

  defp response_type("code"), do: :ok
  defp response_type(_response_type), do: {:error, :unsupported_response_type}

  defp registered_redirect_uri(%{redirect_uris: uris}, uri) when is_binary(uri) do
    if uri in uris, do: {:ok, uri}, else: {:error, :invalid_request}
  end

  defp registered_redirect_uri(_client, _uri), do: {:error, :invalid_request}

  defp code_challenge(%{"code_challenge" => challenge, "code_challenge_method" => "S256"})
       when is_binary(challenge) and byte_size(challenge) == 43,
       do: {:ok, challenge}

  defp code_challenge(_params), do: {:error, :invalid_request}

  defp requested_scopes(nil), do: {:ok, AgentAuth.scopes()}
  defp requested_scopes(""), do: {:ok, AgentAuth.scopes()}

  defp requested_scopes(scope) when is_binary(scope) do
    scopes = scope |> String.split() |> Enum.uniq()

    if scopes != [] and Enum.all?(scopes, &(&1 in AgentAuth.scopes())) and "mcp" in scopes,
      do: {:ok, scopes_for_mcp_request(scopes)},
      else: {:error, :invalid_scope}
  end

  defp requested_scopes(_scope), do: {:error, :invalid_scope}

  defp scopes_for_mcp_request(["mcp"]), do: AgentAuth.scopes()
  defp scopes_for_mcp_request(scopes), do: scopes

  defp resource(nil, issuer), do: {:ok, issuer <> "/mcp"}
  defp resource("", issuer), do: {:ok, issuer <> "/mcp"}
  defp resource(resource, issuer) when resource == issuer <> "/mcp", do: {:ok, resource}
  defp resource(_resource, _issuer), do: {:error, :invalid_target}

  defp state(nil), do: {:ok, nil}

  defp state(value) when is_binary(value) and byte_size(value) <= @maximum_state_length,
    do: {:ok, value}

  defp state(_value), do: {:error, :invalid_request}

  defp binary_parameter(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :invalid_grant}
    end
  end

  defp code_verifier(value) when is_binary(value) and byte_size(value) in 43..128,
    do: {:ok, value}

  defp code_verifier(_value), do: {:error, :invalid_grant}

  defp usable_authorization_code?(code, client_id, redirect_uri, verifier, resource, timestamp) do
    with true <- is_nil(code.consumed_at),
         true <- code.expires_at > timestamp,
         true <- code.client_id == client_id,
         true <- code.redirect_uri == redirect_uri,
         true <- code.resource == resource,
         true <- secure_compare(code.code_challenge, derived_code_challenge(verifier)) do
      :ok
    else
      _invalid -> {:error, :invalid_grant}
    end
  end

  defp usable_refresh_token?(token, client_id, resource, timestamp) do
    if is_nil(token.revoked_at) and token.expires_at > timestamp and token.client_id == client_id and
         token.resource == resource,
       do: :ok,
       else: {:error, :invalid_grant}
  end

  defp authorization_code_grant_enabled?(repo, client_id),
    do: grant_enabled?(repo, client_id, @authorization_code_grant)

  defp refresh_token_grant_enabled?(repo, client_id),
    do: grant_enabled?(repo, client_id, @refresh_token_grant)

  defp grant_enabled?(repo, client_id, grant) do
    case repo.get(Client, client_id) do
      %Client{grant_types: grant_types} ->
        if grant in grant_types, do: :ok, else: {:error, :invalid_grant}

      _client ->
        {:error, :invalid_grant}
    end
  end

  defp active?(token, timestamp) do
    if is_nil(token.revoked_at) and token.expires_at > timestamp,
      do: :ok,
      else: {:error, :invalid_token}
  end

  defp resource_matches?(_token_resource, nil), do: :ok
  defp resource_matches?(resource, resource), do: :ok
  defp resource_matches?(_token_resource, _resource), do: {:error, :invalid_token}

  defp required_scopes?(scopes, required) do
    if Enum.all?(required, &(&1 in String.split(scopes))),
      do: :ok,
      else: {:error, :insufficient_scope}
  end

  defp revoke_access_token(repo, hash, client_id, timestamp) when is_binary(client_id) do
    query = from(token in AccessToken, where: token.token_hash == ^hash)

    repo.update_all(from(token in query, where: token.client_id == ^client_id),
      set: [revoked_at: timestamp]
    )
  end

  defp revoke_access_token(_repo, _hash, _client_id, _timestamp), do: {0, nil}

  defp revoke_refresh_token(repo, hash, client_id, timestamp) when is_binary(client_id) do
    query = from(token in RefreshToken, where: token.token_hash == ^hash)

    repo.update_all(from(token in query, where: token.client_id == ^client_id),
      set: [revoked_at: timestamp]
    )
  end

  defp revoke_refresh_token(_repo, _hash, _client_id, _timestamp), do: {0, nil}

  defp revoke_grant_family(repo, grant_id, timestamp) do
    repo.update_all(
      from(token in AccessToken, where: token.grant_id == ^grant_id and is_nil(token.revoked_at)),
      set: [revoked_at: timestamp]
    )

    repo.update_all(
      from(token in RefreshToken,
        where: token.grant_id == ^grant_id and is_nil(token.revoked_at)
      ),
      set: [revoked_at: timestamp]
    )
  end

  defp transaction_response({:ok, {:ok, response}}), do: {:ok, response}
  defp transaction_response({:ok, {:error, reason}}), do: {:error, reason}
  defp transaction_response({:ok, response}), do: {:ok, response}
  defp transaction_response({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp transaction_response({:error, _reason}), do: {:error, :invalid_grant}

  defp append_query(url, params) do
    uri = URI.parse(url)
    query = uri.query |> Kernel.||("") |> URI.decode_query() |> Map.merge(params)
    %{uri | query: URI.encode_query(query)} |> URI.to_string()
  end

  defp derived_code_challenge(verifier),
    do: :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

  defp secret(prefix),
    do: prefix <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))

  defp digest(value), do: :crypto.hash(:sha256, value)

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_compare(_left, _right), do: false

  defp now(opts), do: Keyword.get(opts, :now, System.system_time(:second))
  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
end
