defmodule TedWeb.CoachingController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ted.Operations
  alias TedWeb.ApiSchemas.{CheckIn, GenericObject, Meal, Profile, Workout}

  tags ["Coaching"]
  security [%{"bearerAuth" => []}]

  plug TedWeb.ApiAuth, [scopes: ["profile:read"]] when action == :get_profile
  plug TedWeb.ApiAuth, [scopes: ["profile:write"]] when action == :update_profile
  plug TedWeb.ApiAuth, [scopes: ["check_ins:write"]] when action == :record_check_in
  plug TedWeb.ApiAuth, [scopes: ["workouts:write"]] when action == :log_workout
  plug TedWeb.ApiAuth, [scopes: ["meals:write"]] when action == :log_meal
  plug TedWeb.ApiAuth, [scopes: ["plans:read"]] when action == :recommend_meal
  plug TedWeb.ApiAuth, [scopes: ["objectives:read"]] when action == :list_objectives
  plug TedWeb.ApiAuth, [scopes: ["objectives:write"]] when action == :set_objective
  plug TedWeb.ApiAuth, [scopes: ["plans:read"]] when action == :get_active_plan
  plug TedWeb.ApiAuth, [scopes: ["plans:write"]] when action in [:build_plan, :review_plan]
  plug TedWeb.ApiAuth, [scopes: ["plans:read"]] when action == :get_today_plan
  plug TedWeb.ApiAuth, [scopes: ["check_ins:read"]] when action == :get_progress

  operation :get_profile,
    operation_id: "get_profile",
    summary: "Read the current coaching profile",
    responses: [ok: {"Coaching profile", "application/json", Profile}]

  operation :update_profile,
    operation_id: "update_profile",
    summary: "Create or update the current coaching profile",
    request_body: {"Profile fields", "application/json", Profile},
    responses: [ok: {"Updated profile", "application/json", Profile}]

  operation :record_check_in,
    operation_id: "record_check_in",
    summary: "Create or replace one daily check-in",
    request_body: {"Daily check-in", "application/json", CheckIn},
    responses: [ok: {"Recorded check-in", "application/json", CheckIn}]

  operation :log_workout,
    operation_id: "log_workout",
    summary: "Log a completed workout",
    request_body: {"Completed workout", "application/json", Workout},
    responses: [created: {"Recorded workout", "application/json", Workout}]

  operation :log_meal,
    operation_id: "log_meal",
    summary: "Log a meal",
    request_body: {"Meal", "application/json", Meal},
    responses: [created: {"Recorded meal", "application/json", Meal}]

  operation :recommend_meal,
    operation_id: "recommend_meal",
    summary: "Suggest a preference-aware meal with supporting evidence",
    request_body: {"Meal constraints", "application/json", GenericObject},
    responses: [ok: {"Meal recommendation", "application/json", GenericObject}]

  operation :list_objectives,
    operation_id: "list_objectives",
    summary: "List coaching objectives",
    responses: [
      ok: {"Coaching objectives", "application/json", %Schema{type: :array, items: GenericObject}}
    ]

  operation :set_objective,
    operation_id: "set_objective",
    summary: "Create or update a coaching objective",
    request_body: {"Objective fields", "application/json", GenericObject},
    responses: [ok: {"Coaching objective", "application/json", GenericObject}]

  operation :get_active_plan,
    operation_id: "get_active_plan",
    summary: "Read the active coaching plan",
    responses: [ok: {"Active coaching plan", "application/json", GenericObject}]

  operation :build_plan,
    operation_id: "build_plan",
    summary: "Build a new coaching plan version",
    parameters: [date: [in: :query, type: :string, required: false]],
    responses: [created: {"New coaching plan", "application/json", GenericObject}]

  operation :review_plan,
    operation_id: "review_plan",
    summary: "Review and optionally adjust the active plan",
    parameters: [date: [in: :query, type: :string, required: false]],
    responses: [created: {"Plan review", "application/json", GenericObject}]

  operation :get_today_plan,
    operation_id: "get_today_plan",
    summary: "Build the daily coaching plan",
    parameters: [date: [in: :query, type: :string, required: false]],
    responses: [ok: {"Daily plan", "application/json", GenericObject}]

  operation :get_progress,
    operation_id: "get_progress",
    summary: "Review recent coaching progress",
    parameters: [
      days: [
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365}
      ]
    ],
    responses: [ok: {"Progress", "application/json", GenericObject}]

  def get_profile(conn, _params), do: execute(conn, "get_profile", %{})
  def update_profile(conn, params), do: execute(conn, "update_profile", params)
  def record_check_in(conn, params), do: execute(conn, "record_check_in", params)
  def log_workout(conn, params), do: execute(conn, "log_workout", params, 201)
  def log_meal(conn, params), do: execute(conn, "log_meal", params, 201)
  def recommend_meal(conn, params), do: execute(conn, "recommend_meal", params)
  def list_objectives(conn, _params), do: execute(conn, "list_objectives", %{})
  def set_objective(conn, params), do: execute(conn, "set_objective", params)
  def get_active_plan(conn, _params), do: execute(conn, "get_active_plan", %{})
  def build_plan(conn, params), do: execute(conn, "build_plan", params, 201)
  def review_plan(conn, params), do: execute(conn, "review_plan", params, 201)
  def get_today_plan(conn, params), do: execute(conn, "get_today_plan", params)

  def get_progress(conn, params) do
    execute(conn, "get_progress", parse_integer(params, "days"))
  end

  defp execute(conn, operation, arguments, success_status \\ 200) do
    TedWeb.ApiResponse.send_result(
      conn,
      Operations.call(operation, arguments, repo(conn), conn.assigns.authorization),
      success_status
    )
  end

  defp parse_integer(params, key) do
    case Map.get(params, key) do
      nil ->
        params

      value when is_integer(value) ->
        params

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> Map.put(params, key, parsed)
          _invalid -> Map.put(params, key, value)
        end
    end
  end

  defp repo(conn), do: conn.private[:ted_index] || Ted.Index.context()
end
