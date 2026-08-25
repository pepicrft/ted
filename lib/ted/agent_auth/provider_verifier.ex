defmodule Ted.AgentAuth.ProviderVerifier do
  @moduledoc "Verifies trusted provider identity assertions and Security Event Tokens."

  @identity_type "urn:ietf:params:oauth:token-type:id-jag"
  @revocation_event "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked"

  @spec identity_type() :: String.t()
  def identity_type, do: @identity_type

  @spec revocation_event() :: String.t()
  def revocation_event, do: @revocation_event

  @spec verify_identity(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def verify_identity(assertion, audience, opts \\ []) do
    with {:ok, header, claims} <- decoded(assertion),
         {:ok, provider} <- trusted_provider(claims["iss"], opts),
         :ok <- validate_header(header, "oauth-id-jag+jwt"),
         {:ok, verified_claims} <- verify_signature(assertion, header, provider, opts),
         :ok <- validate_identity_claims(verified_claims, audience, provider, opts) do
      {:ok, verified_claims}
    end
  end

  @spec verify_event(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def verify_event(token, audience, opts \\ []) do
    with {:ok, header, claims} <- decoded(token),
         {:ok, provider} <- trusted_provider(claims["iss"], opts),
         :ok <- validate_header(header, "secevent+jwt"),
         {:ok, verified_claims} <- verify_signature(token, header, provider, opts),
         :ok <- validate_event_claims(verified_claims, audience, provider, opts) do
      {:ok, verified_claims}
    end
  end

  defp decoded(token) when is_binary(token) do
    with [header, payload, _signature] <- String.split(token, "."),
         {:ok, header_binary} <- Base.url_decode64(header, padding: false),
         {:ok, payload_binary} <- Base.url_decode64(payload, padding: false),
         {:ok, header_map} when is_map(header_map) <- JSON.decode(header_binary),
         {:ok, payload_map} when is_map(payload_map) <- JSON.decode(payload_binary) do
      {:ok, header_map, payload_map}
    else
      _invalid -> {:error, :invalid_request}
    end
  end

  defp decoded(_token), do: {:error, :invalid_request}

  defp trusted_provider(issuer, opts) when is_binary(issuer) do
    providers = Keyword.get(opts, :trusted_providers, [])

    case Enum.find(providers, &(provider_value(&1, :issuer) == issuer)) do
      nil -> {:error, :invalid_issuer}
      provider -> {:ok, provider}
    end
  end

  defp trusted_provider(_issuer, _opts), do: {:error, :invalid_issuer}

  defp validate_header(%{"alg" => alg, "kid" => kid, "typ" => typ}, expected_type)
       when alg in ["RS256", "ES256"] and is_binary(kid) and typ == expected_type,
       do: :ok

  defp validate_header(_header, _type), do: {:error, :invalid_signature}

  defp verify_signature(token, header, provider, opts) do
    client = Keyword.get(opts, :jwks_client, Ted.AgentAuth.JwksClient)
    uri = provider_value(provider, :jwks_uri)

    with true <- is_binary(uri),
         {:ok, %{"keys" => keys}} <- client.fetch(uri, opts),
         %{} = key_map <- Enum.find(keys, &(&1["kid"] == header["kid"])),
         key <- JOSE.JWK.from_map(key_map),
         {true, %JOSE.JWT{fields: claims}, _signature} <-
           JOSE.JWT.verify_strict(key, [header["alg"]], token) do
      {:ok, claims}
    else
      _invalid -> {:error, :invalid_signature}
    end
  end

  defp validate_identity_claims(claims, audience, provider, opts) do
    current_time = Keyword.get(opts, :now, System.system_time(:second))
    maximum_age = Keyword.get(opts, :maximum_auth_age_seconds, 3_600)
    allowed_clients = provider_value(provider, :client_ids) || []

    with :ok <- validate_issuer(claims, provider),
         :ok <- validate_audience(claims, audience),
         :ok <- validate_expiration(claims, current_time),
         :ok <- validate_issued_at(claims, current_time),
         :ok <- validate_identifiers(claims),
         :ok <- validate_client(claims, allowed_clients),
         :ok <- validate_verified_email(claims) do
      validate_authentication_time(claims, current_time, maximum_age)
    end
  end

  defp validate_event_claims(claims, audience, provider, opts) do
    current_time = Keyword.get(opts, :now, System.system_time(:second))

    with :ok <- validate_issuer(claims, provider),
         :ok <- validate_audience(claims, audience),
         :ok <- validate_issued_at(claims, current_time),
         :ok <- validate_identifiers(claims) do
      validate_revocation_event(claims)
    end
  end

  defp validate_issuer(claims, provider) do
    if claims["iss"] == provider_value(provider, :issuer),
      do: :ok,
      else: {:error, :invalid_issuer}
  end

  defp validate_audience(claims, audience) do
    if audience_match?(claims["aud"], audience),
      do: :ok,
      else: {:error, :invalid_audience}
  end

  defp validate_expiration(%{"exp" => expiration}, current_time)
       when is_integer(expiration) and expiration > current_time,
       do: :ok

  defp validate_expiration(_claims, _current_time), do: {:error, :expired}

  defp validate_issued_at(%{"iat" => issued_at}, current_time)
       when is_integer(issued_at) and issued_at <= current_time + 60,
       do: :ok

  defp validate_issued_at(_claims, _current_time), do: {:error, :invalid_request}

  defp validate_identifiers(%{"jti" => jti, "sub" => subject})
       when is_binary(jti) and is_binary(subject),
       do: :ok

  defp validate_identifiers(_claims), do: {:error, :invalid_request}

  defp validate_client(%{"client_id" => client_id}, allowed_clients)
       when is_binary(client_id) do
    if client_id in allowed_clients, do: :ok, else: {:error, :invalid_client_id}
  end

  defp validate_client(_claims, _allowed_clients), do: {:error, :invalid_client_id}

  defp validate_verified_email(%{"email_verified" => true, "email" => email})
       when is_binary(email),
       do: :ok

  defp validate_verified_email(_claims), do: {:error, :missing_verified_email}

  defp validate_authentication_time(
         %{"auth_time" => authentication_time},
         current_time,
         maximum_age
       )
       when is_integer(authentication_time) and authentication_time <= current_time + 60 and
              current_time - authentication_time <= maximum_age,
       do: :ok

  defp validate_authentication_time(_claims, _current_time, _maximum_age),
    do: {:error, :login_required}

  defp validate_revocation_event(%{"events" => events}) when is_map(events) do
    if Map.has_key?(events, @revocation_event), do: :ok, else: {:error, :unsupported_event}
  end

  defp validate_revocation_event(_claims), do: {:error, :unsupported_event}

  defp audience_match?(audience, expected) when is_binary(audience), do: audience == expected
  defp audience_match?(audiences, expected) when is_list(audiences), do: expected in audiences
  defp audience_match?(_audience, _expected), do: false

  defp provider_value(provider, key) do
    Map.get(provider, key) || Map.get(provider, Atom.to_string(key))
  end
end
