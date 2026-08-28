defmodule TedWeb.InterfacesTest do
  use Ted.DataCase, async: true

  alias Ted.Accounts.User
  alias Ted.DataCase

  @default_user_id "00000000-0000-0000-0000-000000000001"

  test "publishes complete agent authorization discovery and instructions" do
    discovery = DataCase.endpoint_conn(:get, "/.well-known/oauth-authorization-server", nil)
    assert discovery.status == 200
    document = JSON.decode!(discovery.resp_body)

    assert document["agent_auth"]["identity_types_supported"] == ["service_auth"]

    assert document["agent_auth"]["identity_assertion"]["assertion_types_supported"] == []
    assert document["agent_auth"]["events_supported"] == []
    assert document["token_endpoint"] =~ "/oauth2/token"
    assert document["authorization_endpoint"] =~ "/oauth2/authorize"
    assert document["registration_endpoint"] =~ "/oauth2/register"
    assert document["code_challenge_methods_supported"] == ["S256"]

    instructions = DataCase.endpoint_conn(:get, "/auth.md", nil)
    assert instructions.status == 200
    assert instructions.resp_body =~ "## 1. Discover"
    assert instructions.resp_body =~ "## 8. Revoke credentials"
    assert instructions.resp_body =~ "Register with service_auth"
    assert instructions.resp_body =~ "anonymous_not_enabled"
    assert instructions.resp_body =~ "Dynamic Client Registration"
    refute instructions.resp_body =~ "/terms"
    refute instructions.resp_body =~ "/privacy"
  end

  test "rejects unadvertised registration flows and obsolete application keys", %{repo: repo} do
    anonymous = DataCase.endpoint_conn(:post, "/agent/identity", %{"type" => "anonymous"})
    assert anonymous.status == 400
    assert JSON.decode!(anonymous.resp_body) == %{"error" => "anonymous_not_enabled"}

    provider =
      DataCase.endpoint_conn(:post, "/agent/identity", %{
        "type" => "identity_assertion",
        "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
        "assertion" => "unused"
      })

    assert provider.status == 400
    assert JSON.decode!(provider.resp_body) == %{"error" => "identity_assertion_not_enabled"}

    obsolete_key =
      :get
      |> Plug.Test.conn("/api/profile")
      |> Plug.Conn.put_private(:ted_index, repo)
      |> Plug.Conn.put_req_header("x-api-key", "obsolete")
      |> TedWeb.Endpoint.call([])

    assert obsolete_key.status == 401
    assert JSON.decode!(obsolete_key.resp_body) == %{"error" => "invalid_token"}
  end

  test "redirects the root to operations and publishes the favicon" do
    home = DataCase.endpoint_conn(:get, "/", nil)

    assert home.status == 302
    assert Plug.Conn.get_resp_header(home, "location") == ["/docs"]

    reference = DataCase.endpoint_conn(:get, "/docs", nil)
    assert reference.status == 200
    assert reference.resp_body =~ "Ted application programming interface reference"
    assert reference.resp_body =~ ~s(rel="icon" href="/favicon.ico")
    assert reference.resp_body =~ "--font-size: 16px"
    assert reference.resp_body =~ ~s(data-part="site-header")

    for path <- ["/terms", "/privacy", "/cookies"] do
      assert DataCase.endpoint_conn(:get, path, nil).status == 404
    end

    open_api = DataCase.endpoint_conn(:get, "/openapi.json", nil)
    paths = open_api.resp_body |> JSON.decode!() |> Map.fetch!("paths")

    refute Map.has_key?(paths, "/terms")
    refute Map.has_key?(paths, "/privacy")
    refute Map.has_key?(paths, "/cookies")

    assert DataCase.endpoint_conn(:post, "/telegram/webhook", %{}).status == 404

    favicon = DataCase.endpoint_conn(:get, "/favicon.ico", nil)
    assert favicon.status == 200
    assert Plug.Conn.get_resp_header(favicon, "content-type") == ["image/vnd.microsoft.icon"]
    assert byte_size(favicon.resp_body) > 100
  end

  test "lists and calls the shared coaching tools through Model Context Protocol", %{repo: repo} do
    assert {:ok, _user} =
             repo.insert(%User{
               id: @default_user_id,
               email: "owner@example.test",
               name: "Owner",
               email_verified_at: DateTime.utc_now()
             })

    access_token = agent_access_token(repo)

    listed =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"},
        access_token
      )

    assert listed.status == 200

    names =
      listed.resp_body |> JSON.decode!() |> get_in(["result", "tools"]) |> Enum.map(& &1["name"])

    assert "set_objective" in names
    assert "review_plan" in names
    assert "recommend_meal" in names

    called =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/call",
          "params" => %{
            "name" => "set_objective",
            "arguments" => %{
              "kind" => "strength",
              "label" => "Deadlift 150 kilograms",
              "target_value" => 150,
              "unit" => "kg"
            }
          }
        },
        access_token
      )

    assert called.status == 200

    result =
      called.resp_body |> JSON.decode!() |> get_in(["result", "structuredContent", "result"])

    assert result["kind"] == "strength"

    recommended =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{
            "name" => "recommend_meal",
            "arguments" => %{"meal_type" => "dinner", "time_available_minutes" => 25}
          }
        },
        access_token
      )

    assert recommended.status == 200

    recommendation =
      recommended.resp_body
      |> JSON.decode!()
      |> get_in(["result", "structuredContent", "result"])

    assert recommendation["suggestions"] != []
    assert recommendation["evidence"] != []
  end

  defp agent_access_token(repo) do
    issuer = TedWeb.Endpoint.url()

    opts = [
      index: repo,
      issuer: issuer,
      user_code_hmac_key: "test-user-code-hmac-key",
      allow_ephemeral_signing_key: true
    ]

    assert {:ok, registration} =
             Ted.AgentAuth.create_service_registration("owner@example.test", opts)

    assert {:ok, user} = Ted.Accounts.get_user_by_email("owner@example.test", repo)

    assert {:ok, _claim} =
             Ted.AgentAuth.confirm_claim(
               registration.claim_attempt_token,
               registration.user_code,
               user,
               opts
             )

    assert {:ok, claimed} = Ted.AgentAuth.exchange_claim(registration.claim_token, opts)

    assert {:ok, token} =
             Ted.AgentAuth.exchange_assertion(
               claimed.identity_assertion,
               issuer <> "/mcp",
               opts
             )

    token.access_token
  end
end
