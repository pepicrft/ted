defmodule TedWeb.InterfacesTest do
  use Ted.DataCase, async: true

  alias Ted.Accounts.User
  alias Ted.DataCase

  @default_user_id "00000000-0000-0000-0000-000000000001"

  test "publishes complete agent authorization discovery and instructions" do
    discovery = DataCase.endpoint_conn(:get, "/.well-known/oauth-authorization-server", nil)
    assert discovery.status == 200
    document = JSON.decode!(discovery.resp_body)

    assert document["agent_auth"]["identity_types_supported"] == [
             "anonymous",
             "identity_assertion",
             "service_auth"
           ]

    assert document["agent_auth"]["events_supported"] != []
    assert document["token_endpoint"] =~ "/oauth2/token"

    instructions = DataCase.endpoint_conn(:get, "/auth.md", nil)
    assert instructions.status == 200
    assert instructions.resp_body =~ "## 1. Discover"
    assert instructions.resp_body =~ "## 8. Revocation"
    assert instructions.resp_body =~ "identity_assertion"
    assert instructions.resp_body =~ "anonymous"
  end

  test "redirects the root to operations and publishes the legal boundary and favicon" do
    home = DataCase.endpoint_conn(:get, "/", nil)

    assert home.status == 302
    assert Plug.Conn.get_resp_header(home, "location") == ["/docs"]

    reference = DataCase.endpoint_conn(:get, "/docs", nil)
    assert reference.status == 200
    assert reference.resp_body =~ "Ted application programming interface reference"
    assert reference.resp_body =~ ~s(rel="icon" href="/favicon.ico")

    terms = DataCase.endpoint_conn(:get, "/terms", nil)
    assert terms.status == 200
    assert terms.resp_body =~ "Your decision and responsibility"
    assert terms.resp_body =~ "Nothing in these terms excludes or limits liability"

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
               name: "Owner"
             })

    listed =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"},
        "test"
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
        "test"
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
        "test"
      )

    assert recommended.status == 200

    recommendation =
      recommended.resp_body
      |> JSON.decode!()
      |> get_in(["result", "structuredContent", "result"])

    assert recommendation["suggestions"] != []
    assert recommendation["evidence"] != []
  end
end
