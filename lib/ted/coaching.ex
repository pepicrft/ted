defmodule Ted.Coaching do
  @moduledoc "Stores coaching inputs and produces plans scoped to one person."

  import Ecto.Query

  alias Ted.Coaching.{
    CheckIn,
    Meal,
    MealRecommender,
    Objective,
    Plan,
    PlanBuilder,
    Planner,
    Profile,
    Review,
    Reviewer,
    Workout
  }

  alias Ted.Repo

  @spec get_profile(Ecto.UUID.t(), module()) :: {:ok, map()} | {:error, :not_found}
  def get_profile(user_id, repo \\ Repo) do
    case repo.get_by(Profile, user_id: user_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile_map(profile)}
    end
  end

  @spec update_profile(Ecto.UUID.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def update_profile(user_id, attrs, repo \\ Repo) when is_map(attrs) do
    profile = repo.get_by(Profile, user_id: user_id) || %Profile{user_id: user_id}

    profile
    |> Profile.changeset(Map.put(attrs, "user_id", user_id))
    |> persist(repo)
    |> map_result(&profile_map/1)
  end

  @spec record_check_in(Ecto.UUID.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def record_check_in(user_id, attrs, repo \\ Repo) when is_map(attrs) do
    with {:ok, date} <- date_value(Map.get(attrs, "date"), Date.utc_today()) do
      check_in = repo.get_by(CheckIn, user_id: user_id, date: date) || %CheckIn{}

      attrs = attrs |> Map.put("user_id", user_id) |> Map.put("date", date)

      check_in
      |> CheckIn.changeset(attrs)
      |> persist(repo)
      |> map_result(&check_in_map/1)
    end
  end

  @spec log_workout(Ecto.UUID.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def log_workout(user_id, attrs, repo \\ Repo) when is_map(attrs) do
    with {:ok, performed_on} <- date_value(Map.get(attrs, "performed_on"), Date.utc_today()) do
      attrs = attrs |> Map.put("user_id", user_id) |> Map.put("performed_on", performed_on)

      %Workout{}
      |> Workout.changeset(attrs)
      |> repo.insert()
      |> map_result(&workout_map/1)
    end
  end

  @spec log_meal(Ecto.UUID.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def log_meal(user_id, attrs, repo \\ Repo) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put("user_id", user_id)
      |> Map.put_new("occurred_at", DateTime.utc_now() |> DateTime.truncate(:microsecond))

    %Meal{}
    |> Meal.changeset(attrs)
    |> repo.insert()
    |> map_result(&meal_map/1)
  end

  @spec recommend_meal(Ecto.UUID.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def recommend_meal(user_id, attrs \\ %{}, repo \\ Repo) when is_map(attrs) do
    with {:ok, date} <- date_value(Map.get(attrs, "date"), Date.utc_today()),
         {:ok, meal_type} <- meal_type_value(Map.get(attrs, "meal_type")),
         {:ok, time_available} <- time_available_value(Map.get(attrs, "time_available_minutes")),
         {:ok, avoid} <- string_list_value(Map.get(attrs, "avoid", [])) do
      profile = repo.get_by(Profile, user_id: user_id) || %Profile{user_id: user_id}
      {day_start, day_end} = day_bounds(date)

      meals =
        repo.all(
          from(meal in Meal,
            where:
              meal.user_id == ^user_id and meal.occurred_at >= ^day_start and
                meal.occurred_at < ^day_end,
            order_by: [asc: meal.occurred_at]
          )
        )

      active_plan = active_plan_record(user_id, repo)
      objectives = active_objective_records(user_id, repo)

      plan_context =
        active_plan ||
          struct(
            Plan,
            PlanBuilder.build(profile, objectives, latest_weight(user_id, repo), 1, date)
          )

      {:ok,
       MealRecommender.build(
         %{date: date, profile: profile, meals: meals, plan: plan_context},
         %{
           "meal_type" => meal_type,
           "time_available_minutes" => time_available,
           "avoid" => avoid
         }
       )}
    end
  end

  @spec list_objectives(Ecto.UUID.t(), module()) :: {:ok, [map()]}
  def list_objectives(user_id, repo \\ Repo) do
    objectives =
      repo.all(
        from(objective in Objective,
          where: objective.user_id == ^user_id,
          order_by: [desc: objective.priority, asc: objective.inserted_at]
        )
      )

    {:ok, Enum.map(objectives, &objective_map/1)}
  end

  @spec set_objective(Ecto.UUID.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def set_objective(user_id, attrs, repo \\ Repo) when is_map(attrs) do
    objective =
      case Map.get(attrs, "id") do
        id when is_binary(id) -> repo.get_by(Objective, id: id, user_id: user_id) || %Objective{}
        _id -> %Objective{}
      end

    objective
    |> Objective.changeset(Map.put(attrs, "user_id", user_id))
    |> persist(repo)
    |> map_result(&objective_map/1)
  end

  @spec active_plan(Ecto.UUID.t(), module()) :: {:ok, map()} | {:error, :not_found}
  def active_plan(user_id, repo \\ Repo) do
    case active_plan_record(user_id, repo) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan_map(plan)}
    end
  end

  @spec build_plan(Ecto.UUID.t(), Date.t(), module()) :: {:ok, map()} | {:error, term()}
  def build_plan(user_id, date \\ Date.utc_today(), repo \\ Repo) do
    profile = repo.get_by(Profile, user_id: user_id) || %Profile{user_id: user_id}
    objectives = active_objective_records(user_id, repo)
    latest_weight = latest_weight(user_id, repo)
    next_version = next_plan_version(user_id, repo)
    attributes = PlanBuilder.build(profile, objectives, latest_weight, next_version, date)

    repo.transaction(fn ->
      supersede_active_plans(user_id, repo)

      case repo.insert(Plan.changeset(%Plan{}, attributes)) do
        {:ok, plan} -> plan_map(plan)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @spec review_plan(Ecto.UUID.t(), Date.t(), module()) :: {:ok, map()} | {:error, term()}
  def review_plan(user_id, date \\ Date.utc_today(), repo \\ Repo) do
    case active_plan_record(user_id, repo) do
      %Plan{} = plan ->
        check_ins = review_check_ins(user_id, plan.starts_on, date, repo)
        workouts = review_workouts(user_id, plan.starts_on, date, repo)
        evaluation = Reviewer.evaluate(plan, check_ins, workouts, date)
        persist_review(user_id, plan, evaluation, date, repo)

      nil ->
        {:error, :not_found}
    end
  end

  @spec today_plan(Ecto.UUID.t(), Date.t(), module()) :: {:ok, map()}
  def today_plan(user_id, date \\ Date.utc_today(), repo \\ Repo) do
    profile = repo.get_by(Profile, user_id: user_id) || %Profile{user_id: user_id}
    start_date = Date.add(date, -6)
    {day_start, day_end} = day_bounds(date)

    check_in = repo.get_by(CheckIn, user_id: user_id, date: date)

    workouts =
      repo.all(
        from(workout in Workout,
          where:
            workout.user_id == ^user_id and workout.performed_on >= ^start_date and
              workout.performed_on <= ^date,
          order_by: [desc: workout.performed_on, desc: workout.inserted_at]
        )
      )

    meals =
      repo.all(
        from(meal in Meal,
          where:
            meal.user_id == ^user_id and meal.occurred_at >= ^day_start and
              meal.occurred_at < ^day_end,
          order_by: [asc: meal.occurred_at]
        )
      )

    active_plan = active_plan_record(user_id, repo)
    objectives = active_objective_records(user_id, repo)

    plan_context =
      active_plan ||
        struct(
          Plan,
          PlanBuilder.build(profile, objectives, latest_weight(user_id, repo), 1, date)
        )

    {:ok,
     Planner.build(%{
       date: date,
       profile: profile,
       check_in: check_in,
       workouts: workouts,
       meals: meals,
       plan: plan_context,
       objectives: objectives
     })}
  end

  @spec progress(Ecto.UUID.t(), pos_integer(), module()) :: {:ok, map()}
  def progress(user_id, days \\ 30, repo \\ Repo)

  def progress(user_id, days, repo) when is_integer(days) and days > 0 and days <= 365 do
    since = Date.add(Date.utc_today(), -(days - 1))

    check_ins =
      repo.all(
        from(check_in in CheckIn,
          where: check_in.user_id == ^user_id and check_in.date >= ^since,
          order_by: [asc: check_in.date]
        )
      )

    workouts =
      repo.all(
        from(workout in Workout,
          where: workout.user_id == ^user_id and workout.performed_on >= ^since,
          order_by: [asc: workout.performed_on]
        )
      )

    {:ok,
     %{
       period_days: days,
       since: since,
       check_ins: Enum.map(check_ins, &check_in_map/1),
       workouts: Enum.map(workouts, &workout_map/1),
       summary: %{
         check_in_days: length(check_ins),
         workouts_completed: length(workouts),
         weight_change_kg: weight_change(check_ins)
       }
     }}
  end

  def progress(_user_id, _days, _repo), do: {:error, :invalid_arguments}

  defp persist_review(user_id, plan, evaluation, date, repo) do
    repo.transaction(fn ->
      with {:ok, next_plan} <- maybe_create_adjusted_plan(user_id, plan, evaluation, date, repo),
           attributes <-
             evaluation
             |> Map.put(:user_id, user_id)
             |> Map.put(:plan_id, plan.id)
             |> Map.put(:next_plan_id, next_plan && next_plan.id)
             |> Map.put(:reviewed_on, date),
           {:ok, review} <- repo.insert(Review.changeset(%Review{}, attributes)) do
        review_map(review, next_plan)
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp maybe_create_adjusted_plan(_user_id, _plan, %{status: status}, _date, _repo)
       when status != "adjusted",
       do: {:ok, nil}

  defp maybe_create_adjusted_plan(user_id, plan, evaluation, date, repo) do
    strategy = apply_changes(plan.strategy, evaluation.decision["changes"])
    superseded_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    with {:ok, _plan} <-
           plan
           |> Plan.changeset(%{status: "superseded", superseded_at: superseded_at})
           |> repo.update() do
      repo.insert(
        Plan.changeset(%Plan{}, %{
          user_id: user_id,
          version: plan.version + 1,
          status: "active",
          starts_on: date,
          review_on: Date.add(date, 14),
          objective_snapshot: plan.objective_snapshot,
          strategy: strategy,
          rationale: evaluation.rationale,
          evidence: plan.evidence,
          created_by: "ted_review"
        })
      )
    end
  end

  defp apply_changes(strategy, changes) do
    Enum.reduce(changes || [], strategy, fn
      %{"path" => [section, key], "to" => value}, current ->
        put_in(current, [Access.key(section, %{}), Access.key(key)], value)

      _change, current ->
        current
    end)
  end

  defp active_plan_record(user_id, repo) do
    repo.one(
      from(plan in Plan,
        where: plan.user_id == ^user_id and plan.status == "active",
        order_by: [desc: plan.version],
        limit: 1
      )
    )
  end

  defp active_objective_records(user_id, repo) do
    repo.all(
      from(objective in Objective,
        where: objective.user_id == ^user_id and objective.status == "active",
        order_by: [desc: objective.priority, asc: objective.inserted_at]
      )
    )
  end

  defp latest_weight(user_id, repo) do
    repo.one(
      from(check_in in CheckIn,
        where: check_in.user_id == ^user_id and not is_nil(check_in.weight_kg),
        order_by: [desc: check_in.date],
        limit: 1,
        select: check_in.weight_kg
      )
    )
  end

  defp next_plan_version(user_id, repo) do
    case repo.one(from(plan in Plan, where: plan.user_id == ^user_id, select: max(plan.version))) do
      nil -> 1
      version -> version + 1
    end
  end

  defp supersede_active_plans(user_id, repo) do
    repo.update_all(
      from(plan in Plan, where: plan.user_id == ^user_id and plan.status == "active"),
      set: [
        status: "superseded",
        superseded_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      ]
    )
  end

  defp review_check_ins(user_id, start_date, date, repo) do
    repo.all(
      from(check_in in CheckIn,
        where:
          check_in.user_id == ^user_id and check_in.date >= ^start_date and
            check_in.date <= ^date,
        order_by: [asc: check_in.date]
      )
    )
  end

  defp review_workouts(user_id, start_date, date, repo) do
    repo.all(
      from(workout in Workout,
        where:
          workout.user_id == ^user_id and workout.performed_on >= ^start_date and
            workout.performed_on <= ^date,
        order_by: [asc: workout.performed_on]
      )
    )
  end

  defp persist(%Ecto.Changeset{data: %{id: nil}} = changeset, repo), do: repo.insert(changeset)
  defp persist(changeset, repo), do: repo.update(changeset)

  defp map_result({:ok, record}, mapper), do: {:ok, mapper.(record)}
  defp map_result({:error, reason}, _mapper), do: {:error, reason}

  defp date_value(nil, default), do: {:ok, default}
  defp date_value(%Date{} = date, _default), do: {:ok, date}
  defp date_value(value, _default) when is_binary(value), do: Date.from_iso8601(value)
  defp date_value(_value, _default), do: {:error, :invalid_arguments}

  defp meal_type_value(nil), do: {:ok, "any"}

  defp meal_type_value(value)
       when value in ~w(any breakfast lunch dinner snack),
       do: {:ok, value}

  defp meal_type_value(_value), do: {:error, :invalid_arguments}

  defp time_available_value(nil), do: {:ok, nil}

  defp time_available_value(value) when is_integer(value) and value >= 1 and value <= 180,
    do: {:ok, value}

  defp time_available_value(_value), do: {:error, :invalid_arguments}

  defp string_list_value(values) when is_list(values) do
    if Enum.all?(values, &is_binary/1), do: {:ok, values}, else: {:error, :invalid_arguments}
  end

  defp string_list_value(_values), do: {:error, :invalid_arguments}

  defp day_bounds(date) do
    {:ok, start_time} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    {start_time, DateTime.add(start_time, 1, :day)}
  end

  defp weight_change(check_ins) do
    weights = check_ins |> Enum.map(& &1.weight_kg) |> Enum.reject(&is_nil/1)

    case weights do
      [first | _rest] when length(weights) > 1 ->
        last = List.last(weights)
        last |> Decimal.sub(first) |> Decimal.round(2) |> Decimal.to_float()

      _weights ->
        nil
    end
  end

  defp profile_map(profile) do
    %{
      id: profile.id,
      user_id: profile.user_id,
      timezone: profile.timezone,
      primary_goal: profile.primary_goal,
      experience_level: profile.experience_level,
      training_days_per_week: profile.training_days_per_week,
      session_minutes: profile.session_minutes,
      equipment: profile.equipment,
      dietary_preferences: profile.dietary_preferences,
      daily_energy_target_kcal: profile.daily_energy_target_kcal,
      daily_protein_target_g: profile.daily_protein_target_g,
      created_at: profile.inserted_at,
      updated_at: profile.updated_at
    }
  end

  defp check_in_map(check_in) do
    %{
      id: check_in.id,
      date: check_in.date,
      weight_kg: decimal(check_in.weight_kg),
      sleep_hours: decimal(check_in.sleep_hours),
      energy: check_in.energy,
      soreness: check_in.soreness,
      pain: check_in.pain,
      nutrition_adherence: check_in.nutrition_adherence,
      note: check_in.note,
      created_at: check_in.inserted_at,
      updated_at: check_in.updated_at
    }
  end

  defp workout_map(workout) do
    %{
      id: workout.id,
      performed_on: workout.performed_on,
      name: workout.name,
      duration_minutes: workout.duration_minutes,
      perceived_exertion: workout.perceived_exertion,
      movements: workout.movements,
      notes: workout.notes,
      created_at: workout.inserted_at
    }
  end

  defp meal_map(meal) do
    %{
      id: meal.id,
      occurred_at: meal.occurred_at,
      description: meal.description,
      energy_kcal: meal.energy_kcal,
      protein_g: decimal(meal.protein_g),
      carbohydrate_g: decimal(meal.carbohydrate_g),
      fat_g: decimal(meal.fat_g),
      created_at: meal.inserted_at
    }
  end

  defp objective_map(objective) do
    %{
      id: objective.id,
      kind: objective.kind,
      label: objective.label,
      metric: objective.metric,
      baseline_value: decimal(objective.baseline_value),
      target_value: decimal(objective.target_value),
      unit: objective.unit,
      target_date: objective.target_date,
      priority: objective.priority,
      status: objective.status,
      details: objective.details,
      created_at: objective.inserted_at,
      updated_at: objective.updated_at
    }
  end

  defp plan_map(plan) do
    %{
      id: plan.id,
      version: plan.version,
      status: plan.status,
      starts_on: plan.starts_on,
      review_on: plan.review_on,
      objective_snapshot: plan.objective_snapshot,
      strategy: plan.strategy,
      rationale: plan.rationale,
      evidence: plan.evidence,
      created_by: plan.created_by,
      created_at: plan.inserted_at
    }
  end

  defp review_map(review, next_plan) do
    %{
      id: review.id,
      reviewed_on: review.reviewed_on,
      status: review.status,
      observations: review.observations,
      decision: review.decision,
      rationale: review.rationale,
      confidence: review.confidence,
      plan_id: review.plan_id,
      next_plan: next_plan && plan_map(next_plan),
      created_at: review.inserted_at
    }
  end

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = value), do: Decimal.to_float(value)
end
