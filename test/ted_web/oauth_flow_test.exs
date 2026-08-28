defmodule TedWeb.OAuthFlowTest do
  use Ted.DataCase, async: true

  alias Ted.Accounts
  alias Ted.Accounts.User
  alias Ted.AgentAuth
  alias Ted.DataCase
  alias Ted.OAuth

  test "a dynamically registered client receives refreshable access to the Model Context Protocol",
       %{
         repo: repo
       } do
    redirect_uri = "http://127.0.0.1:47832/callback"

    registration =
      DataCase.endpoint_conn(
        :post,
        "/oauth2/register",
        %{
          "client_name" => "Hermes",
          "redirect_uris" => [redirect_uri],
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "token_endpoint_auth_method" => "none"
        }
      )

    assert registration.status == 201
    client = JSON.decode!(registration.resp_body)
    assert client["client_name"] == "Hermes"
    assert client["redirect_uris"] == [redirect_uri]
    refute Map.has_key?(client, "client_secret")

    assert {:ok, user} =
             Accounts.create_verified_agent_user(
               %{"email" => "hermes-owner@example.test", "name" => "Hermes Owner"},
               repo
             )

    verifier = String.duplicate("ted-proof-key-", 4)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => client["client_id"],
        "redirect_uri" => redirect_uri,
        "state" => "hermes-state",
        "scope" => "mcp profile:read objectives:read",
        "resource" => TedWeb.Endpoint.url() <> "/mcp",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    consent = browser_conn(:get, "/oauth2/authorize?#{query}", nil, repo, %{ted_user_id: user.id})
    assert consent.status == 200
    assert consent.resp_body =~ "Connect Hermes?"
    assert consent.resp_body =~ "Allow access"
    assert consent.resp_body =~ "--font-size: 16px"
    assert consent.resp_body =~ ~s(data-part="site-header")

    assert Plug.Conn.get_resp_header(consent, "content-security-policy") == [
             "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self' http://127.0.0.1:47832; base-uri 'none'; frame-ancestors 'none'"
           ]

    csrf_token = csrf_token(consent.resp_body)

    approval =
      consent
      |> next_browser_conn(
        :post,
        "/oauth2/authorize",
        %{
          "decision" => "approve",
          "authorization_request_id" => authorization_request_id(consent.resp_body),
          "_csrf_token" => csrf_token
        },
        repo
      )

    assert approval.status == 302
    redirect = approval |> Plug.Conn.get_resp_header("location") |> List.first() |> URI.parse()
    params = URI.decode_query(redirect.query)

    assert redirect.scheme == "http"
    assert redirect.host == "127.0.0.1"
    assert params["state"] == "hermes-state"
    assert params["iss"] == TedWeb.Endpoint.url()
    assert is_binary(params["code"])

    token =
      form_conn(
        :post,
        "/oauth2/token",
        %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "redirect_uri" => redirect_uri,
          "code" => params["code"],
          "code_verifier" => verifier,
          "resource" => TedWeb.Endpoint.url() <> "/mcp"
        },
        repo
      )

    assert token.status == 200
    token_response = JSON.decode!(token.resp_body)
    assert token_response["token_type"] == "Bearer"
    assert token_response["refresh_token"]
    assert token_response["scope"] == "mcp profile:read objectives:read"

    listed =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"},
        token_response["access_token"]
      )

    assert listed.status == 200

    assert :ok = OAuth.revoke(token_response["access_token"], nil, repo: repo)

    still_authorized =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"},
        token_response["access_token"]
      )

    assert still_authorized.status == 200

    refreshed =
      form_conn(
        :post,
        "/oauth2/token",
        %{
          "grant_type" => "refresh_token",
          "client_id" => client["client_id"],
          "refresh_token" => token_response["refresh_token"],
          "resource" => TedWeb.Endpoint.url() <> "/mcp"
        },
        repo
      )

    assert refreshed.status == 200
    refreshed_response = JSON.decode!(refreshed.resp_body)
    assert refreshed_response["access_token"] != token_response["access_token"]
    assert refreshed_response["refresh_token"] != token_response["refresh_token"]

    reused_refresh =
      form_conn(
        :post,
        "/oauth2/token",
        %{
          "grant_type" => "refresh_token",
          "client_id" => client["client_id"],
          "refresh_token" => token_response["refresh_token"],
          "resource" => TedWeb.Endpoint.url() <> "/mcp"
        },
        repo
      )

    assert reused_refresh.status == 400
    assert JSON.decode!(reused_refresh.resp_body)["error"] == "invalid_grant"

    revoked_after_replay =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{"jsonrpc" => "2.0", "id" => 3, "method" => "tools/list"},
        refreshed_response["access_token"]
      )

    assert revoked_after_replay.status == 401
  end

  test "an mcp-only authorization request expands to the complete coaching scope set", %{
    repo: repo
  } do
    client = register_client(repo, ["authorization_code", "refresh_token"])
    verifier = String.duplicate("ted-mcp-only-proof-", 4)
    resource = TedWeb.Endpoint.url() <> "/mcp"
    user = verified_user(repo, "mcp-only-owner@example.test")

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => client.client_id,
        "redirect_uri" => hd(client.redirect_uris),
        "scope" => "mcp",
        "resource" => resource,
        "code_challenge" => :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false),
        "code_challenge_method" => "S256"
      })

    consent = browser_conn(:get, "/oauth2/authorize?#{query}", nil, repo, %{ted_user_id: user.id})

    assert consent.status == 200

    for scope <- AgentAuth.scopes() do
      assert consent.resp_body =~ "<li>#{scope}</li>"
    end
  end

  test "an authorization-code replay revokes the whole authorization grant", %{repo: repo} do
    client = register_client(repo, ["authorization_code", "refresh_token"])
    user = verified_user(repo, "code-replay-owner@example.test")
    verifier = String.duplicate("ted-proof-key-", 4)
    resource = TedWeb.Endpoint.url() <> "/mcp"

    {:ok, code} =
      OAuth.issue_authorization_code(authorization_request(client, verifier, resource), user.id,
        repo: repo
      )

    assert {:ok, credentials} =
             OAuth.exchange_authorization_code(exchange_params(client, code, verifier, resource),
               repo: repo,
               issuer: TedWeb.Endpoint.url()
             )

    assert {:error, :invalid_grant} =
             OAuth.exchange_authorization_code(exchange_params(client, code, verifier, resource),
               repo: repo,
               issuer: TedWeb.Endpoint.url()
             )

    assert {:error, :invalid_token} =
             OAuth.authorize(credentials.access_token, ["mcp"], repo: repo, resource: resource)
  end

  test "a client without the refresh grant does not receive a refresh token", %{repo: repo} do
    client = register_client(repo, ["authorization_code"])
    user = verified_user(repo, "no-refresh-owner@example.test")
    verifier = String.duplicate("ted-proof-key-", 4)
    resource = TedWeb.Endpoint.url() <> "/mcp"

    {:ok, code} =
      OAuth.issue_authorization_code(authorization_request(client, verifier, resource), user.id,
        repo: repo
      )

    assert {:ok, credentials} =
             OAuth.exchange_authorization_code(exchange_params(client, code, verifier, resource),
               repo: repo,
               issuer: TedWeb.Endpoint.url()
             )

    refute Map.has_key?(credentials, :refresh_token)
  end

  test "a stale consent page cannot approve a later authorization request", %{repo: repo} do
    user = verified_user(repo, "consent-owner@example.test")
    client = register_client(repo, ["authorization_code", "refresh_token"])
    resource = TedWeb.Endpoint.url() <> "/mcp"
    verifier = String.duplicate("ted-proof-key-", 4)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => client.client_id,
        "redirect_uri" => hd(client.redirect_uris),
        "scope" => "mcp",
        "resource" => resource,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    consent = browser_conn(:get, "/oauth2/authorize?#{query}", nil, repo, %{ted_user_id: user.id})
    assert consent.status == 200

    later_client = register_client(repo, ["authorization_code", "refresh_token"])

    later_query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => later_client.client_id,
        "redirect_uri" => hd(later_client.redirect_uris),
        "scope" => "mcp",
        "resource" => resource,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    later_consent =
      next_browser_conn(consent, :get, "/oauth2/authorize?#{later_query}", nil, repo)

    assert later_consent.status == 200

    rejected_approval =
      next_browser_conn(
        later_consent,
        :post,
        "/oauth2/authorize",
        %{
          "decision" => "approve",
          "authorization_request_id" => authorization_request_id(consent.resp_body),
          "_csrf_token" => csrf_token(later_consent.resp_body)
        },
        repo
      )

    assert rejected_approval.status == 400
  end

  test "signing in preserves the pending authorization request across session renewal", %{
    repo: repo
  } do
    password = "a secure test password"

    {:ok, user} =
      %User{}
      |> User.agent_signup_changeset(%{
        "email" => "sign-in-owner@example.test",
        "name" => "Sign-in Owner",
        "password" => password
      })
      |> Ecto.Changeset.change(
        email_verified_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      )
      |> repo.insert()

    client = register_client(repo, ["authorization_code", "refresh_token"])
    verifier = String.duplicate("ted-proof-key-", 4)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => client.client_id,
        "redirect_uri" => hd(client.redirect_uris),
        "scope" => "mcp",
        "resource" => TedWeb.Endpoint.url() <> "/mcp",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    authorization = browser_conn(:get, "/oauth2/authorize?#{query}", nil, repo, %{})

    assert authorization.status == 302
    assert Plug.Conn.get_resp_header(authorization, "location") == ["/oauth2/authorize/sign-in"]

    sign_in = next_browser_conn(authorization, :get, "/oauth2/authorize/sign-in", nil, repo)
    assert sign_in.status == 200

    authenticated =
      next_browser_conn(
        sign_in,
        :post,
        "/oauth2/authorize/sign-in",
        %{
          "email" => user.email,
          "password" => password,
          "_csrf_token" => csrf_token(sign_in.resp_body)
        },
        repo
      )

    assert authenticated.status == 302
    assert Plug.Conn.get_resp_header(authenticated, "location") == ["/oauth2/authorize"]

    consent = next_browser_conn(authenticated, :get, "/oauth2/authorize", nil, repo)

    assert consent.status == 200
    assert consent.resp_body =~ "Connect Ted Test Client?"
  end

  test "dynamic client registration rejects an untrusted HTTP redirect address" do
    response =
      DataCase.endpoint_conn(:post, "/oauth2/register", %{
        "redirect_uris" => ["http://example.test/callback"]
      })

    assert response.status == 400
    assert JSON.decode!(response.resp_body)["error"] == "invalid_redirect_uri"
  end

  defp browser_conn(method, path, body, repo, session) do
    method
    |> Plug.Test.conn(path, encoded_body(body))
    |> Plug.Test.init_test_session(session)
    |> browser_private(repo)
    |> maybe_form_content_type(body)
    |> TedWeb.Endpoint.call([])
  end

  defp next_browser_conn(previous, method, path, body, repo) do
    method
    |> Plug.Test.conn(path, encoded_body(body))
    |> Plug.Test.recycle_cookies(previous)
    |> browser_private(repo)
    |> maybe_form_content_type(body)
    |> TedWeb.Endpoint.call([])
  end

  defp form_conn(method, path, form, repo) do
    method
    |> Plug.Test.conn(path, URI.encode_query(form))
    |> Plug.Conn.put_private(:ted_index, repo)
    |> Plug.Conn.put_private(:ted_rate_limit_namespace, System.unique_integer([:positive]))
    |> Plug.Conn.put_private(:ted_rate_limits, unrestricted_rate_limits())
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> TedWeb.Endpoint.call([])
  end

  defp browser_private(conn, repo) do
    conn
    |> Plug.Conn.put_private(:ted_index, repo)
    |> Plug.Conn.put_private(:ted_rate_limit_namespace, System.unique_integer([:positive]))
    |> Plug.Conn.put_private(:ted_rate_limits, unrestricted_rate_limits())
    |> Plug.Conn.put_req_header("accept", "text/html")
  end

  defp maybe_form_content_type(conn, nil), do: conn

  defp maybe_form_content_type(conn, _body),
    do: Plug.Conn.put_req_header(conn, "content-type", "application/x-www-form-urlencoded")

  defp encoded_body(nil), do: nil
  defp encoded_body(body), do: URI.encode_query(body)

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp authorization_request_id(body) do
    [_, request_id] = Regex.run(~r/name="authorization_request_id" value="([^"]+)"/, body)
    request_id
  end

  defp register_client(repo, grant_types) do
    {:ok, client} =
      OAuth.register_client(
        %{
          "client_name" => "Ted Test Client",
          "redirect_uris" => ["http://127.0.0.1:47832/callback"],
          "grant_types" => grant_types
        },
        repo: repo
      )

    client
  end

  defp verified_user(repo, email) do
    {:ok, user} =
      Accounts.create_verified_agent_user(%{"email" => email, "name" => "Ted Owner"}, repo)

    user
  end

  defp authorization_request(client, verifier, resource) do
    %{
      client: %{id: client.client_id},
      redirect_uri: hd(client.redirect_uris),
      code_challenge: :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false),
      scopes: ["mcp"],
      resource: resource
    }
  end

  defp exchange_params(client, code, verifier, resource) do
    %{
      "client_id" => client.client_id,
      "code" => code,
      "redirect_uri" => hd(client.redirect_uris),
      "code_verifier" => verifier,
      "resource" => resource
    }
  end

  defp unrestricted_rate_limits do
    [
      website: [scale_ms: 60_000, limit: 100_000],
      documentation: [scale_ms: 60_000, limit: 100_000],
      api: [scale_ms: 60_000, limit: 100_000],
      authentication: [scale_ms: 60_000, limit: 100_000],
      model_context_protocol: [scale_ms: 60_000, limit: 100_000]
    ]
  end
end
