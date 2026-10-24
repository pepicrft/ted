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

    assert Map.has_key?(paths, "/api/workout-templates")
    assert Map.has_key?(paths, "/api/workout-templates/{id}")
    assert Map.has_key?(paths, "/api/workout-templates/{id}/preparation")

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
    assert "save_workout_template" in names
    assert "prepare_workout" in names

    for name <-
          ~w(start_workout get_current_workout get_workout record_workout_set finish_workout) do
      assert name in names
    end

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

    template = %{
      "name" => "Full-body strength A",
      "estimated_duration_minutes" => 50,
      "image_url" => "/assets/workouts/full-body-strength-a.png",
      "image_alt" => "A three-panel barbell workout reference illustration.",
      "movements" => [
        %{
          "id" => "back-squat",
          "name" => "Barbell squat",
          "sets" => 3,
          "repetitions" => "5",
          "rest_seconds" => 150,
          "instructions" => "Use a controlled load and stop if pain increases.",
          "image_url" => "/assets/exercises/barbell-squat.png",
          "image_alt" => "Original reference illustration of a barbell back squat.",
          "video_url" => "https://www.youtube.com/watch?v=8PMjqgR8Wa8"
        }
      ]
    }

    saved =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{
          "jsonrpc" => "2.0",
          "id" => 4,
          "method" => "tools/call",
          "params" => %{"name" => "save_workout_template", "arguments" => template}
        },
        access_token
      )

    assert saved.status == 200

    saved_template =
      saved.resp_body
      |> JSON.decode!()
      |> get_in(["result", "structuredContent", "result"])

    assert saved_template["version"] == 1

    prepared =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "tools/call",
          "params" => %{
            "name" => "prepare_workout",
            "arguments" => %{"id" => saved_template["id"]}
          }
        },
        access_token
      )

    assert prepared.status == 200

    prepared_workout =
      prepared.resp_body
      |> JSON.decode!()
      |> get_in(["result", "structuredContent", "result", "workout"])

    assert prepared_workout["workout_template_id"] == saved_template["id"]
    assert prepared_workout["workout_template_version"] == 1

    assert [
             %{"video_url" => "https://www.youtube.com/watch?v=8PMjqgR8Wa8"}
           ] = prepared_workout["movements"]
  end

  test "persists live workouts across both interfaces and isolates seeded people", %{repo: repo} do
    Code.eval_file(Path.expand("../../priv/repo/seeds.exs", __DIR__))
    origin = TedWeb.Endpoint.url()
    owner_token = agent_access_token(repo, "owner@ted.local")
    owner_web_token = agent_access_token(repo, "owner@ted.local", origin)
    alex_token = agent_access_token(repo, "alex@ted.local")
    alex_web_token = agent_access_token(repo, "alex@ted.local", origin)

    owner_today = tool_result(owner_token, "get_today_plan")
    alex_today = tool_result(alex_token, "get_today_plan")
    assert owner_today["training"]["title"] == "Full-body strength A"
    assert alex_today["training"]["title"] == "Foundational full-body"
    assert tool_result(owner_token, "get_profile")["equipment"] == ["barbell", "rack", "bench"]
    assert tool_result(alex_token, "get_profile")["equipment"] == []

    refute tool_result(owner_token, "list_objectives") ==
             tool_result(alex_token, "list_objectives")

    templates = tool_result(owner_token, "list_workout_templates")
    selected = Enum.find(templates, &(&1["name"] == "Full-body strength B"))

    built =
      DataCase.endpoint_conn(
        :post,
        "/api/plan",
        %{"workout_template_ids" => [selected["id"]]},
        owner_web_token
      )

    assert built.status == 201

    assert JSON.decode!(built.resp_body)["strategy"]["training"]["workout_templates"]
           |> hd()
           |> Map.fetch!("id") == selected["id"]

    started = tool_result(owner_token, "start_workout")
    id = started["id"]
    assert started["name"] == "Full-body strength B"
    assert started["progress"]["completed_sets"] == 0
    assert started["progress"]["remaining_sets"] == 9
    assert tool_result(owner_token, "start_workout")["id"] == id
    assert tool_result(owner_token, "get_workout", %{"id" => id})["id"] == id
    assert tool_result(owner_token, "get_today_plan")["current_workout"]["id"] == id

    for {method, path, body} <- [
          {:get, "/api/workouts/#{id}", nil},
          {:put, "/api/workouts/#{id}/sets",
           %{"movement_id" => "deadlift", "set_number" => 1, "repetitions" => 5}},
          {:post, "/api/workouts/#{id}/finish", %{"status" => "cancelled"}}
        ] do
      denied = DataCase.endpoint_conn(method, path, body, alex_web_token)
      assert denied.status == 404
    end

    denied_tool = mcp_call(alex_token, "get_workout", %{"id" => id})
    assert denied_tool["isError"]
    assert [%{"text" => "not_found"}] = denied_tool["content"]

    set = %{"movement_id" => "deadlift", "set_number" => 1, "repetitions" => 5, "load_kg" => 87.5}
    recorded = DataCase.endpoint_conn(:put, "/api/workouts/#{id}/sets", set, owner_web_token)
    assert recorded.status == 200
    assert JSON.decode!(recorded.resp_body)["progress"]["remaining_sets"] == 8
    persisted = tool_result(owner_token, "get_current_workout")
    assert [%{"repetitions" => 5, "load_kg" => 87.5}] = persisted["completed_sets"]
    assert persisted["progress"]["next_set"]["movement"]["id"] == "deadlift"
    assert persisted["progress"]["next_set"]["set_number"] == 2
    retried = tool_result(owner_token, "record_workout_set", Map.put(set, "id", id))
    assert retried["progress"]["completed_sets"] == 1

    invalid_set = set |> Map.put("id", id) |> Map.put("repetitions", -1)
    rejected = mcp_call(owner_token, "record_workout_set", invalid_set)
    assert rejected["isError"]
    assert [%{"text" => "invalid_arguments"}] = rejected["content"]

    incomplete =
      DataCase.endpoint_conn(
        :post,
        "/api/workouts/#{id}/finish",
        %{"status" => "completed"},
        owner_web_token
      )

    assert incomplete.status == 409
    assert JSON.decode!(incomplete.resp_body)["error"] == "workout_incomplete"

    for movement <- ["deadlift", "overhead-press", "split-squat"], number <- 1..3 do
      tool_result(owner_token, "record_workout_set", %{
        "id" => id,
        "movement_id" => movement,
        "set_number" => number,
        "repetitions" => 5
      })
    end

    finished = tool_result(owner_token, "finish_workout", %{"id" => id, "status" => "completed"})
    assert finished["status"] == "completed"
    assert finished["progress"]["remaining_sets"] == 0
    assert finished["movements"] == started["movements"]

    assert DataCase.endpoint_conn(:get, "/api/workouts/current", nil, owner_web_token).status ==
             404

    assert tool_result(alex_token, "get_progress")["workouts"] == []
    assert tool_result(owner_token, "get_progress")["summary"]["workouts_completed"] == 2

    alex_started = DataCase.endpoint_conn(:post, "/api/workouts/start", %{}, alex_web_token)
    assert alex_started.status == 200
    alex_id = JSON.decode!(alex_started.resp_body)["id"]
    assert tool_result(alex_token, "get_current_workout")["id"] == alex_id

    cancelled =
      DataCase.endpoint_conn(
        :post,
        "/api/workouts/#{alex_id}/finish",
        %{"status" => "cancelled"},
        alex_web_token
      )

    assert cancelled.status == 200
    assert tool_result(alex_token, "get_workout", %{"id" => alex_id})["status"] == "cancelled"

    paths =
      DataCase.endpoint_conn(:get, "/openapi.json", nil).resp_body
      |> JSON.decode!()
      |> Map.fetch!("paths")

    for {path, method, name} <- [
          {"/api/workouts/start", "post", "start_workout"},
          {"/api/workouts/current", "get", "get_current_workout"},
          {"/api/workouts/{id}", "get", "get_workout"},
          {"/api/workouts/{id}/sets", "put", "record_workout_set"},
          {"/api/workouts/{id}/finish", "post", "finish_workout"}
        ] do
      assert paths[path][method]["operationId"] == name
      assert {:ok, _operation} = Ted.Operations.fetch(name)
    end
  end

  defp mcp_call(token, name, arguments) do
    conn =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => name, "arguments" => arguments}
        },
        token
      )

    assert conn.status == 200
    JSON.decode!(conn.resp_body)["result"]
  end

  defp tool_result(token, name, arguments \\ %{}) do
    result = mcp_call(token, name, arguments)
    refute result["isError"], inspect(result)
    result["structuredContent"]["result"]
  end

  defp agent_access_token(
         repo,
         email \\ "owner@example.test",
         resource \\ TedWeb.Endpoint.url() <> "/mcp"
       ) do
    issuer = TedWeb.Endpoint.url()

    opts = [
      index: repo,
      issuer: issuer,
      user_code_hmac_key: "test-user-code-hmac-key",
      allow_ephemeral_signing_key: true
    ]

    assert {:ok, registration} =
             Ted.AgentAuth.create_service_registration(email, opts)

    assert {:ok, user} = Ted.Accounts.get_user_by_email(email, repo)

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
               resource,
               opts
             )

    token.access_token
  end
end
