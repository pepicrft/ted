defmodule TedWeb.AgentIdentityController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ted.AgentAuth
  alias Ted.Index
  alias TedWeb.PublicOrigin

  tags ["Agent authentication"]
  security []

  operation :create,
    operation_id: "register_agent_identity",
    summary: "Start an auth.md agent registration",
    request_body:
      {"Agent registration", "application/json",
       %Schema{
         type: :object,
         properties: %{
           type: %Schema{type: :string, enum: ["anonymous", "identity_assertion", "service_auth"]},
           login_hint: %Schema{type: :string, format: :email},
           assertion_type: %Schema{type: :string},
           assertion: %Schema{type: :string, writeOnly: true}
         },
         required: [:type]
       }},
    responses: [ok: {"Registration ceremony", "application/json", %Schema{type: :object}}]

  operation :claim,
    operation_id: "start_agent_claim",
    summary: "Start an anonymous claim when that optional flow is enabled",
    request_body:
      {"Claim request", "application/json", %Schema{type: :object, additionalProperties: true}},
    responses: [ok: {"Claim ceremony", "application/json", %Schema{type: :object}}]

  def create(conn, %{"type" => "service_auth", "login_hint" => email}) do
    opts = auth_opts(conn)

    case AgentAuth.create_service_registration(email, opts) do
      {:ok, result} -> json(conn, registration_response(result, opts))
      {:error, reason} -> registration_error(conn, reason)
    end
  end

  def create(conn, %{"type" => "anonymous"}) do
    opts = auth_opts(conn)

    case AgentAuth.create_anonymous_registration(opts) do
      {:ok, result} -> json(conn, anonymous_response(result, opts))
      {:error, reason} -> registration_error(conn, reason)
    end
  end

  def create(conn, %{
        "type" => "identity_assertion",
        "assertion_type" => assertion_type,
        "assertion" => assertion
      }) do
    opts = auth_opts(conn)

    case AgentAuth.create_identity_registration(assertion_type, assertion, opts) do
      {:ok, result} -> json(conn, identity_response(result))
      {:interaction_required, result} -> interaction_required(conn, result, opts)
      {:error, reason} -> registration_error(conn, reason)
    end
  end

  def create(conn, _params), do: conn |> put_status(400) |> json(%{error: "invalid_request"})

  def claim(conn, %{"claim_token" => claim_token, "email" => email}) do
    opts = auth_opts(conn)

    case AgentAuth.start_anonymous_claim(claim_token, email, opts) do
      {:ok, result} -> json(conn, anonymous_claim_response(result, opts))
      {:error, reason} -> registration_error(conn, reason)
    end
  end

  def claim(conn, _params), do: registration_error(conn, :invalid_request)

  defp registration_response(result, opts) do
    registration = result.registration
    origin = Keyword.fetch!(opts, :issuer)
    expires_in = max(registration.claim_attempt_expires_at - System.system_time(:second), 0)

    %{
      registration_id: registration.id,
      registration_type: registration.registration_type,
      claim_url: origin <> "/agent/identity/claim",
      claim_token: result.claim_token,
      claim_token_expires: iso8601(registration.expires_at),
      post_claim_scopes: AgentAuth.agent_scopes(),
      claim: %{
        user_code: result.user_code,
        expires_in: expires_in,
        verification_uri:
          origin <>
            "/agent/identity/claim?claim_attempt_token=" <>
            URI.encode_www_form(result.claim_attempt_token),
        interval: AgentAuth.poll_interval(opts)
      }
    }
  end

  defp anonymous_response(result, opts) do
    registration = result.registration

    %{
      registration_id: registration.id,
      registration_type: registration.registration_type,
      identity_assertion: result.identity_assertion,
      assertion_expires: result.assertion_expires,
      pre_claim_scopes: AgentAuth.pre_claim_scopes(),
      claim_url: Keyword.fetch!(opts, :issuer) <> "/agent/identity/claim",
      claim_token: result.claim_token,
      claim_token_expires: iso8601(registration.expires_at),
      post_claim_scopes: AgentAuth.agent_scopes()
    }
  end

  defp identity_response(result) do
    %{
      registration_id: result.registration.id,
      registration_type: result.registration.registration_type,
      identity_assertion: result.identity_assertion,
      assertion_expires: result.assertion_expires,
      scopes: AgentAuth.agent_scopes()
    }
  end

  defp anonymous_claim_response(result, opts) do
    registration = result.registration
    origin = Keyword.fetch!(opts, :issuer)

    %{
      registration_id: registration.id,
      claim_attempt_id: registration.id,
      status: "initiated",
      expires_at: iso8601(registration.claim_attempt_expires_at),
      claim_attempt: claim_block(result, origin, opts)
    }
  end

  defp interaction_required(conn, result, opts) do
    registration = registration_response(result, opts)

    conn
    |> put_status(401)
    |> json(
      registration
      |> Map.put(:error, "interaction_required")
      |> Map.put(
        :message,
        "The verified email belongs to an existing account and must be linked by its owner."
      )
    )
  end

  defp claim_block(result, origin, opts) do
    registration = result.registration

    %{
      user_code: result.user_code,
      expires_in: max(registration.claim_attempt_expires_at - System.system_time(:second), 0),
      verification_uri:
        origin <>
          "/agent/identity/claim?claim_attempt_token=" <>
          URI.encode_www_form(result.claim_attempt_token),
      interval: AgentAuth.poll_interval(opts)
    }
  end

  defp registration_error(conn, reason) do
    status =
      cond do
        reason == :rate_limited -> 429
        reason == :login_required -> 401
        true -> 400
      end

    conn |> put_status(status) |> json(%{error: to_string(reason)})
  end

  defp iso8601(unix_time) do
    case DateTime.from_unix(unix_time) do
      {:ok, date_time} -> DateTime.to_iso8601(date_time)
      {:error, _reason} -> nil
    end
  end

  defp auth_opts(conn) do
    [
      index: conn.private[:ted_index] || Index.context(),
      issuer: PublicOrigin.from_conn(conn),
      api_key: conn.private[:ted_api_key] || Application.get_env(:ted, :api_key),
      network_address: conn.remote_ip |> :inet.ntoa() |> to_string()
    ]
  end
end
