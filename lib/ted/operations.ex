defmodule Ted.Operations do
  @moduledoc "The shared operation catalog for web and Model Context Protocol clients."

  alias Ted.Coaching
  alias Ted.Index

  @spec all() :: [map()]
  def all do
    [
      %{
        name: "health",
        description: "Check that Ted and its PostgreSQL database are ready.",
        scope: nil,
        inputSchema: object_schema(),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "get_profile",
        description: "Read the current person's coaching goals and constraints.",
        scope: "profile:read",
        inputSchema: object_schema(),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "update_profile",
        description: "Create or update the current person's coaching goals and constraints.",
        scope: "profile:write",
        inputSchema: profile_schema(),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "record_check_in",
        description: "Record readiness, recovery, weight, and an optional note for one day.",
        scope: "check_ins:write",
        inputSchema: check_in_schema(),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "log_workout",
        description: "Record a completed strength or conditioning session.",
        scope: "workouts:write",
        inputSchema: workout_schema(),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "log_meal",
        description: "Record a meal with optional energy and macronutrient estimates.",
        scope: "meals:write",
        inputSchema: meal_schema(),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "recommend_meal",
        description:
          "Suggest concrete meals from the person's dietary preferences, active plan, and today's recorded estimates, with supporting evidence and limitations.",
        scope: "plans:read",
        inputSchema: meal_recommendation_schema(),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "list_objectives",
        description: "List the person's measurable coaching objectives in priority order.",
        scope: "objectives:read",
        inputSchema: object_schema(),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "set_objective",
        description:
          "Create or update a measurable fat loss, muscle gain, strength, or consistency objective.",
        scope: "objectives:write",
        inputSchema: objective_schema(),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "get_active_plan",
        description: "Read the active, versioned strategy and the evidence used to create it.",
        scope: "plans:read",
        inputSchema: object_schema(),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "build_plan",
        description:
          "Build a new plan version from the profile, active objectives, and latest weight record.",
        scope: "plans:write",
        inputSchema: object_schema(%{"date" => date_schema()}),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "review_plan",
        description:
          "Review the active plan and make at most one bounded adjustment from recorded trends.",
        scope: "plans:write",
        inputSchema: object_schema(%{"date" => date_schema()}),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "get_today_plan",
        description:
          "Build today's strength, recovery, and nutrition priorities from recorded data.",
        scope: "plans:read",
        inputSchema: object_schema(%{"date" => date_schema()}),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "get_progress",
        description: "Review check-ins, workouts, and weight change over a recent period.",
        scope: "check_ins:read",
        inputSchema: object_schema(%{"days" => integer_schema(1, 365)}),
        annotations: %{readOnlyHint: true}
      }
    ]
  end

  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(name) when is_binary(name) do
    case Enum.find(all(), &(&1.name == name)) do
      nil -> :error
      operation -> {:ok, operation}
    end
  end

  @spec call(String.t(), map(), module(), map()) :: {:ok, term()} | {:error, term()}
  def call(name, arguments, repo \\ Index.context(), authorization \\ %{})

  def call("health", _arguments, repo, _authorization) do
    case Index.health(repo) do
      :ok -> {:ok, %{status: "ok"}}
      {:error, reason} -> {:error, reason}
    end
  end

  def call("get_profile", _arguments, repo, authorization),
    do: with_user(authorization, &Coaching.get_profile(&1, repo))

  def call("update_profile", arguments, repo, authorization) when is_map(arguments),
    do: with_user(authorization, &Coaching.update_profile(&1, arguments, repo))

  def call("record_check_in", arguments, repo, authorization) when is_map(arguments),
    do: with_user(authorization, &Coaching.record_check_in(&1, arguments, repo))

  def call("log_workout", arguments, repo, authorization) when is_map(arguments),
    do: with_user(authorization, &Coaching.log_workout(&1, arguments, repo))

  def call("log_meal", arguments, repo, authorization) when is_map(arguments),
    do: with_user(authorization, &Coaching.log_meal(&1, arguments, repo))

  def call("recommend_meal", arguments, repo, authorization) when is_map(arguments),
    do: with_user(authorization, &Coaching.recommend_meal(&1, arguments, repo))

  def call("list_objectives", _arguments, repo, authorization),
    do: with_user(authorization, &Coaching.list_objectives(&1, repo))

  def call("set_objective", arguments, repo, authorization) when is_map(arguments),
    do: with_user(authorization, &Coaching.set_objective(&1, arguments, repo))

  def call("get_active_plan", _arguments, repo, authorization),
    do: with_user(authorization, &Coaching.active_plan(&1, repo))

  def call("build_plan", arguments, repo, authorization) when is_map(arguments) do
    with {:ok, date} <- optional_date(Map.get(arguments, "date")) do
      with_user(authorization, &Coaching.build_plan(&1, date, repo))
    end
  end

  def call("review_plan", arguments, repo, authorization) when is_map(arguments) do
    with {:ok, date} <- optional_date(Map.get(arguments, "date")) do
      with_user(authorization, &Coaching.review_plan(&1, date, repo))
    end
  end

  def call("get_today_plan", arguments, repo, authorization) when is_map(arguments) do
    with {:ok, date} <- optional_date(Map.get(arguments, "date")) do
      with_user(authorization, &Coaching.today_plan(&1, date, repo))
    end
  end

  def call("get_progress", arguments, repo, authorization) when is_map(arguments) do
    days = Map.get(arguments, "days", 30)
    with_user(authorization, &Coaching.progress(&1, days, repo))
  end

  def call(_name, _arguments, _repo, _authorization), do: {:error, :invalid_arguments}

  defp with_user(%{user_id: user_id}, callback) when is_binary(user_id), do: callback.(user_id)
  defp with_user(_authorization, _callback), do: {:error, :forbidden}

  defp optional_date(nil), do: {:ok, Date.utc_today()}
  defp optional_date(%Date{} = date), do: {:ok, date}
  defp optional_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp optional_date(_value), do: {:error, :invalid_arguments}

  defp profile_schema do
    object_schema(%{
      "timezone" => string_schema(),
      "primary_goal" => enum_schema(~w(strength muscle_gain fat_loss general_fitness)),
      "experience_level" => enum_schema(~w(beginner intermediate advanced)),
      "training_days_per_week" => integer_schema(1, 7),
      "session_minutes" => integer_schema(15, 180),
      "equipment" => array_schema(string_schema()),
      "dietary_preferences" => array_schema(string_schema()),
      "daily_energy_target_kcal" => integer_schema(800, 8_000),
      "daily_protein_target_g" => integer_schema(20, 500)
    })
  end

  defp check_in_schema do
    object_schema(%{
      "date" => date_schema(),
      "weight_kg" => number_schema(20, 500),
      "sleep_hours" => number_schema(0, 24),
      "energy" => integer_schema(1, 5),
      "soreness" => integer_schema(1, 5),
      "pain" => integer_schema(0, 10),
      "nutrition_adherence" => integer_schema(1, 5),
      "note" => string_schema()
    })
  end

  defp workout_schema do
    object_schema(
      %{
        "performed_on" => date_schema(),
        "name" => string_schema(),
        "duration_minutes" => integer_schema(1, 480),
        "perceived_exertion" => integer_schema(1, 10),
        "movements" => array_schema(%{type: "object", additionalProperties: true}),
        "notes" => string_schema()
      },
      ["name"]
    )
  end

  defp meal_schema do
    object_schema(
      %{
        "occurred_at" => %{type: "string", format: "date-time"},
        "description" => string_schema(),
        "energy_kcal" => integer_schema(0, 10_000),
        "protein_g" => number_schema(0, 1_000),
        "carbohydrate_g" => number_schema(0, 2_000),
        "fat_g" => number_schema(0, 1_000)
      },
      ["description"]
    )
  end

  defp meal_recommendation_schema do
    object_schema(%{
      "date" => date_schema(),
      "meal_type" => enum_schema(~w(any breakfast lunch dinner snack)),
      "time_available_minutes" => integer_schema(1, 180),
      "avoid" => array_schema(string_schema())
    })
  end

  defp objective_schema do
    object_schema(
      %{
        "id" => string_schema(),
        "kind" => enum_schema(~w(fat_loss muscle_gain body_recomposition strength consistency)),
        "label" => string_schema(),
        "metric" => string_schema(),
        "baseline_value" => number_schema(-1_000_000, 1_000_000),
        "target_value" => number_schema(-1_000_000, 1_000_000),
        "unit" => string_schema(),
        "target_date" => date_schema(),
        "priority" => integer_schema(1, 5),
        "status" => enum_schema(~w(active achieved paused)),
        "details" => %{type: "object", additionalProperties: true}
      },
      ["kind", "label"]
    )
  end

  defp object_schema(properties \\ %{}, required \\ []) do
    %{type: "object", properties: properties, required: required, additionalProperties: false}
  end

  defp string_schema, do: %{type: "string"}
  defp date_schema, do: %{type: "string", format: "date"}
  defp enum_schema(values), do: %{type: "string", enum: values}
  defp array_schema(items), do: %{type: "array", items: items}

  defp integer_schema(minimum, maximum),
    do: %{type: "integer", minimum: minimum, maximum: maximum}

  defp number_schema(minimum, maximum),
    do: %{type: "number", minimum: minimum, maximum: maximum}
end
