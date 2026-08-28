defmodule TedWeb.OAuthAuthorizeController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ted.Accounts
  alias Ted.OAuth
  alias TedWeb.PublicOrigin

  @authorization_request_ttl_seconds 300

  tags ["OAuth"]
  security []

  operation :authorize,
    operation_id: "authorize_oauth_client",
    summary: "Start authorization-code access for a registered client",
    parameters: [
      response_type: [in: :query, type: :string, required: true],
      client_id: [in: :query, type: :string, required: true],
      redirect_uri: [in: :query, type: :string, required: true],
      scope: [in: :query, type: :string],
      state: [in: :query, type: :string],
      resource: [in: :query, type: :string],
      code_challenge: [in: :query, type: :string, required: true],
      code_challenge_method: [in: :query, type: :string, required: true]
    ],
    responses: [
      ok: {"Consent page", "text/html", %Schema{type: :string}},
      found: {"Sign-in or client redirect", "text/html", %Schema{type: :string}},
      bad_request: {"Invalid authorization request", "text/html", %Schema{type: :string}}
    ]

  operation :approve,
    operation_id: "approve_oauth_client_authorization",
    summary: "Approve or deny an authorization request",
    request_body:
      {"Decision", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           decision: %Schema{type: :string, enum: ["approve", "deny"]},
           authorization_request_id: %Schema{type: :string}
         },
         required: [:decision, :authorization_request_id]
       }},
    responses: [found: {"Client redirect", "text/html", %Schema{type: :string}}]

  operation :sign_in,
    operation_id: "show_oauth_authorization_sign_in",
    summary: "Show sign-in for an OAuth authorization request",
    responses: [ok: {"Sign-in page", "text/html", %Schema{type: :string}}]

  operation :authenticate,
    operation_id: "authenticate_oauth_authorization_user",
    summary: "Authenticate the person approving an OAuth authorization request",
    request_body:
      {"Credentials", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           email: %Schema{type: :string, format: :email},
           password: %Schema{type: :string, format: :password, writeOnly: true}
         },
         required: [:email, :password]
       }},
    responses: [
      found: {"Continue authorization", "text/html", %Schema{type: :string}},
      unprocessable_entity: {"Credentials rejected", "text/html", %Schema{type: :string}}
    ]

  operation :sign_out,
    operation_id: "sign_out_oauth_authorization_user",
    summary: "End the browser session used for OAuth authorization",
    request_body: {"Sign-out", "application/x-www-form-urlencoded", %Schema{type: :object}},
    responses: [found: {"Return to sign-in", "text/html", %Schema{type: :string}}]

  def authorize(conn, params) when map_size(params) > 0 do
    case OAuth.authorization_request(params, oauth_opts(conn)) do
      {:ok, request} ->
        request = Map.merge(request, %{id: authorization_request_id(), expires_at: expires_at()})

        conn
        |> put_session(:ted_oauth_authorization, request)
        |> render_or_request_sign_in(request)

      {:error, reason} ->
        send_page(conn, 400, error_page(reason))
    end
  end

  def authorize(conn, _params) do
    case authorization_request(conn) do
      {:ok, request} -> render_or_request_sign_in(conn, request)
      {:error, reason} -> send_page(conn, 400, error_page(reason))
    end
  end

  def approve(conn, %{"decision" => "approve", "authorization_request_id" => request_id}) do
    with {:ok, request} <- authorization_request(conn, request_id),
         {:ok, user} <- verified_user(conn),
         {:ok, code} <- OAuth.issue_authorization_code(request, user.id, oauth_opts(conn)) do
      conn
      |> delete_session(:ted_oauth_authorization)
      |> redirect(
        external: OAuth.authorization_redirect(request, code, PublicOrigin.from_conn(conn))
      )
    else
      {:error, reason} -> send_page(conn, 400, error_page(reason))
    end
  end

  def approve(conn, %{"decision" => "deny", "authorization_request_id" => request_id}) do
    case authorization_request(conn, request_id) do
      {:ok, request} ->
        conn
        |> delete_session(:ted_oauth_authorization)
        |> redirect(external: denial_redirect(request))

      {:error, reason} ->
        send_page(conn, 400, error_page(reason))
    end
  end

  def approve(conn, _params), do: send_page(conn, 400, error_page(:invalid_request))

  def sign_in(conn, _params) do
    case authorization_request(conn) do
      {:ok, request} -> send_page(conn, 200, sign_in_page(request, nil))
      {:error, reason} -> send_page(conn, 400, error_page(reason))
    end
  end

  def authenticate(conn, %{"email" => email, "password" => password}) do
    case authorization_request(conn) do
      {:ok, request} ->
        authenticate_authorization_user(conn, request, email, password)

      {:error, reason} ->
        send_page(conn, 400, error_page(reason))
    end
  end

  def authenticate(conn, _params) do
    render_sign_in_error(conn, "Enter your email and password.")
  end

  def sign_out(conn, _params) do
    conn
    |> configure_session(renew: true)
    |> delete_session(:ted_user_id)
    |> redirect(to: "/oauth2/authorize/sign-in")
  end

  defp render_or_request_sign_in(conn, request) do
    case verified_user(conn) do
      {:ok, user} -> send_page(conn, 200, consent_page(request, user))
      {:error, _reason} -> redirect(conn, to: "/oauth2/authorize/sign-in")
    end
  end

  defp authenticate_authorization_user(conn, request, email, password) do
    case Accounts.authenticate_user(email, password, repo(conn)) do
      {:ok, user} ->
        case email_verified(user) do
          :ok ->
            conn
            |> configure_session(renew: true)
            |> put_session(:ted_oauth_authorization, request)
            |> put_session(:ted_user_id, user.id)
            |> redirect(to: "/oauth2/authorize")

          {:error, :email_unverified} ->
            render_sign_in_error(conn, "Verify your email before authorizing a client.")
        end

      {:error, :invalid_credentials} ->
        render_sign_in_error(conn, "The email or password is incorrect.")
    end
  end

  defp render_sign_in_error(conn, message) do
    case authorization_request(conn) do
      {:ok, request} -> send_page(conn, 422, sign_in_page(request, message))
      {:error, reason} -> send_page(conn, 400, error_page(reason))
    end
  end

  defp authorization_request(conn, expected_id \\ nil) do
    with {:ok, request} <-
           stored_authorization_request(get_session(conn, :ted_oauth_authorization)),
         :ok <- authorization_request_active?(request),
         :ok <- authorization_request_matches?(request, expected_id) do
      {:ok, request}
    end
  end

  defp stored_authorization_request(
         %{
           client: %{id: client_id, name: client_name},
           id: request_id,
           expires_at: expires_at,
           redirect_uri: redirect_uri,
           code_challenge: code_challenge,
           scopes: scopes,
           resource: resource
         } = request
       ) do
    values = [client_id, client_name, request_id, redirect_uri, code_challenge, resource]

    if Enum.all?(values, &is_binary/1) and is_integer(expires_at) and is_list(scopes),
      do: {:ok, request},
      else: {:error, :invalid_request}
  end

  defp stored_authorization_request(_request), do: {:error, :invalid_request}

  defp authorization_request_active?(%{expires_at: expires_at}) do
    if expires_at > System.system_time(:second), do: :ok, else: {:error, :invalid_request}
  end

  defp authorization_request_matches?(_request, nil), do: :ok

  defp authorization_request_matches?(%{id: request_id}, expected_id) do
    if request_id_matches?(request_id, expected_id), do: :ok, else: {:error, :invalid_request}
  end

  defp verified_user(conn) do
    with user_id when is_binary(user_id) <- get_session(conn, :ted_user_id),
         {:ok, user} <- Accounts.get_user(user_id, repo(conn)),
         :ok <- email_verified(user) do
      {:ok, user}
    else
      _error -> {:error, :not_authenticated}
    end
  end

  defp email_verified(%{email_verified_at: %DateTime{}}), do: :ok
  defp email_verified(_user), do: {:error, :email_unverified}

  defp denial_redirect(request) do
    params = %{"error" => "access_denied"}

    params =
      if is_binary(request.state), do: Map.put(params, "state", request.state), else: params

    append_query(request.redirect_uri, params)
  end

  defp append_query(url, params) do
    uri = URI.parse(url)
    query = uri.query |> Kernel.||("") |> URI.decode_query() |> Map.merge(params)
    %{uri | query: URI.encode_query(query)} |> URI.to_string()
  end

  defp consent_page(request, user) do
    scope_list = Enum.map_join(request.scopes, &"<li>#{escape(&1)}</li>")

    page("""
    <main id="oauth-authorization-consent">
      <p data-part="eyebrow">Ted connection request</p>
      <h1>Connect #{escape(request.client.name)}?</h1>
      <p><strong>#{escape(user.email)}</strong> will grant this client access to your Ted coaching account.</p>
      <p>The client requests:</p>
      <ul>#{scope_list}</ul>
      <form method="post" action="/oauth2/authorize">
        #{csrf_field()}
        <input type="hidden" name="authorization_request_id" value="#{escape(request.id)}">
        <button type="submit" name="decision" value="approve">Allow access</button>
        <button type="submit" name="decision" value="deny" data-part="secondary-button">Deny</button>
      </form>
      <form method="post" action="/oauth2/authorize/sign-out" data-part="sign-out">
        #{csrf_field()}
        <button type="submit" data-part="link-button">Use another account</button>
      </form>
    </main>
    """)
  end

  defp sign_in_page(request, error) do
    page("""
    <main id="oauth-authorization-sign-in">
      <p data-part="eyebrow">Ted connection request</p>
      <h1>Sign in to connect #{escape(request.client.name)}</h1>
      <p>Use the verified Ted account whose coaching records you want to share.</p>
      #{error_message(error)}
      <form method="post" action="/oauth2/authorize/sign-in">
        #{csrf_field()}
        <label for="email">Email</label>
        <input id="email" name="email" type="email" autocomplete="email" maxlength="254" required autofocus>
        <label for="password">Password</label>
        <input id="password" name="password" type="password" autocomplete="current-password" minlength="12" maxlength="72" required>
        <button type="submit">Sign in</button>
      </form>
      <p data-part="notice">Need an account? Create one through Ted's agent registration flow, then return to this page.</p>
    </main>
    """)
  end

  defp error_page(reason) do
    page("""
    <main id="oauth-authorization-error">
      <p data-part="eyebrow">Ted connection request</p>
      <h1>Connection unavailable</h1>
      <p>#{escape(error_message_text(reason))}</p>
    </main>
    """)
  end

  defp error_message_text(:invalid_scope), do: "The requested permissions are not supported."

  defp error_message_text(:invalid_target),
    do: "This request does not target Ted's Model Context Protocol server."

  defp error_message_text(:unsupported_response_type),
    do: "Only authorization-code requests are supported."

  defp error_message_text(:not_authenticated), do: "Sign in before approving this request."
  defp error_message_text(_reason), do: "This authorization request is invalid or has expired."

  defp page(content) do
    TedWeb.Theme.inject("""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="robots" content="noindex,nofollow">
        <link rel="icon" href="/favicon.ico" sizes="any">
        <title>Ted connection request</title>
        <style>
          /* ted-theme */
          main { width: min(var(--form-width), calc(100% - 2rem)); margin: 2rem auto; border: 1px solid var(--border); padding: 1rem; }
          [data-part="eyebrow"] { margin: 0 0 .5rem; font-weight: 700; }
          [data-part="notice"] { color: var(--muted); margin-top: 1.5rem; }
          [data-part="error"] { padding: .5rem; color: var(--danger-text); background: var(--danger-background); border: 1px solid var(--danger-border); }
          h1 { margin: 0 0 1rem; font-weight: 700; }
          p { margin: .5rem 0 1rem; }
          ul { padding-left: 1.25rem; }
          form { display: grid; gap: .75rem; margin-top: 1.5rem; }
          [data-part="sign-out"] { margin-top: .75rem; }
          form button { justify-self: start; margin-top: .25rem; }
          [data-part="secondary-button"] { color: var(--text); background: var(--button); border-color: var(--border); }
          [data-part="secondary-button"]:hover { background: var(--button-hover); }
          [data-part="link-button"] { padding: 0; color: var(--link); background: transparent; border: 0; text-align: left; }
          [data-part="link-button"]:hover { color: var(--link-hover); text-decoration: underline; }
        </style>
      </head>
      <body>#{TedWeb.Theme.header()}#{content}</body>
    </html>
    """)
  end

  defp error_message(nil), do: ""
  defp error_message(message), do: ~s(<p data-part="error">#{escape(message)}</p>)

  defp csrf_field do
    ~s(<input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}">)
  end

  defp authorization_request_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp expires_at, do: System.system_time(:second) + @authorization_request_ttl_seconds

  defp request_id_matches?(request_id, expected_id)
       when byte_size(request_id) == byte_size(expected_id),
       do: Plug.Crypto.secure_compare(request_id, expected_id)

  defp request_id_matches?(_request_id, _expected_id), do: false

  defp send_page(conn, status, body) do
    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
    )
    |> send_resp(status, body)
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp oauth_opts(conn), do: [repo: repo(conn), issuer: PublicOrigin.from_conn(conn)]
  defp repo(conn), do: conn.private[:ted_index] || Ted.Index.context()
end
