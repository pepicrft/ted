defmodule Ted.Coaching.Planner do
  @moduledoc "Builds a conservative daily recommendation from recorded coaching data."

  alias Ted.Coaching.MealRecommender

  @spec build(map()) :: map()
  def build(%{date: date, profile: profile, check_in: check_in} = facts) do
    readiness = readiness(check_in)
    training = training_plan(readiness, facts)
    meal_recommendation = MealRecommender.build(facts)
    nutrition = nutrition_plan(profile, facts.meals, facts.plan, meal_recommendation)

    %{
      date: date,
      readiness: readiness,
      message: message(readiness, training, nutrition),
      priorities: priorities(readiness, nutrition),
      training: training,
      nutrition: nutrition,
      objectives: Enum.map(facts.objectives, &objective_summary/1),
      active_plan: plan_summary(facts.plan),
      basis: %{
        latest_check_in_date: check_in && check_in.date,
        workouts_last_7_days: length(facts.workouts),
        meals_logged_today: length(facts.meals)
      }
    }
  end

  defp readiness(nil), do: %{score: 70, label: "unknown", reason: "No check-in recorded today."}

  defp readiness(%{pain: pain}) when is_integer(pain) and pain >= 4 do
    %{
      score: 0,
      label: "safety_hold",
      reason: "Today's check-in includes a meaningful pain signal."
    }
  end

  defp readiness(check_in) do
    energy = check_in.energy || 3
    soreness = check_in.soreness || 3
    sleep = decimal_to_float(check_in.sleep_hours) || 7.0
    score = round(50 + energy * 8 - soreness * 5 + min(sleep, 9.0) * 3) |> min(100) |> max(0)

    label =
      cond do
        score >= 75 -> "ready"
        score >= 55 -> "steady"
        true -> "recover"
      end

    %{score: score, label: label, reason: "Based on energy, soreness, and sleep."}
  end

  defp training_plan(%{label: "recover"}, _facts) do
    %{
      kind: "recovery",
      title: "Recovery session",
      duration_minutes: 25,
      instructions: [
        "Walk or cycle at a conversational pace for 20 minutes.",
        "Finish with five minutes of comfortable mobility.",
        "Stop if pain increases or movement quality deteriorates."
      ]
    }
  end

  defp training_plan(%{label: "safety_hold"}, _facts) do
    %{
      kind: "safety_hold",
      title: "Pause loaded training",
      duration_minutes: 0,
      instructions: [
        "Do not train through meaningful, worsening, or unexplained pain.",
        "Ask a qualified health professional for an assessment before progressing the plan."
      ]
    }
  end

  defp training_plan(_readiness, %{profile: profile, workouts: workouts, plan: plan}) do
    target =
      get_in(plan.strategy, ["training", "days_per_week"]) || profile.training_days_per_week

    volume_multiplier = get_in(plan.strategy, ["training", "volume_multiplier"]) || 1.0

    if length(workouts) >= target do
      %{
        kind: "recovery",
        title: "Easy movement",
        duration_minutes: 30,
        instructions: ["Take an easy walk and arrive fresh for the next strength session."]
      }
    else
      session = if rem(length(workouts), 2) == 0, do: "A", else: "B"

      %{
        kind: "strength",
        title: "Full-body strength #{session}",
        duration_minutes: profile.session_minutes,
        instructions: strength_instructions(session, profile.equipment, volume_multiplier),
        volume_multiplier: volume_multiplier,
        effort_guidance: "Finish most working sets with about two repetitions still possible."
      }
    end
  end

  defp strength_instructions("A", equipment, multiplier) do
    sets = adjusted_sets(multiplier)

    if "barbell" in equipment do
      ["Squat: #{sets} sets of 5", "Bench press: #{sets} sets of 5", "Row: #{sets} sets of 8"]
    else
      [
        "Goblet squat: #{sets} sets of 8",
        "Push-up: #{sets} comfortable sets",
        "Row: #{sets} sets of 10"
      ]
    end
  end

  defp strength_instructions("B", equipment, multiplier) do
    sets = adjusted_sets(multiplier)

    if "barbell" in equipment do
      [
        "Deadlift: #{sets} sets of 5",
        "Overhead press: #{sets} sets of 5",
        "Split squat: #{sets} sets of 8"
      ]
    else
      [
        "Hip hinge: #{sets} sets of 10",
        "Pike push-up: #{sets} comfortable sets",
        "Split squat: #{sets} sets of 8"
      ]
    end
  end

  defp nutrition_plan(profile, meals, plan, meal_recommendation) do
    consumed_energy = Enum.reduce(meals, 0, &((&1.energy_kcal || 0) + &2))

    consumed_protein =
      Enum.reduce(meals, 0.0, fn meal, total ->
        total + (decimal_to_float(meal.protein_g) || 0.0)
      end)

    %{
      energy_target_kcal:
        plan_value(plan, ["nutrition", "energy_target_kcal"], profile.daily_energy_target_kcal),
      protein_target_g:
        plan_value(plan, ["nutrition", "protein_target_g"], profile.daily_protein_target_g),
      energy_logged_kcal: consumed_energy,
      protein_logged_g: Float.round(consumed_protein, 1),
      guidance: meal_recommendation.guidance,
      next_meal: meal_recommendation
    }
  end

  defp priorities(%{label: "recover"}, nutrition),
    do: ["Protect recovery", nutrition.guidance]

  defp priorities(%{label: "safety_hold"}, _nutrition),
    do: ["Protect health", "Do not progress training through meaningful pain"]

  defp priorities(_readiness, nutrition),
    do: ["Train with clean technique", nutrition.guidance]

  defp message(%{label: "recover"}, _training, _nutrition),
    do: "Today is for rebuilding. A lighter day is still part of the plan."

  defp message(%{label: "safety_hold"}, _training, _nutrition),
    do: "Your plan can wait. Meaningful pain deserves attention before progression."

  defp message(_readiness, training, _nutrition),
    do:
      "Keep it simple today: #{training.title}, one useful meal at a time, and an honest check-in."

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp decimal_to_float(value) when is_number(value), do: value / 1

  defp adjusted_sets(multiplier), do: multiplier |> Kernel.*(3) |> round() |> max(2) |> min(4)

  defp plan_value(nil, _path, fallback), do: fallback
  defp plan_value(plan, path, fallback), do: get_in(plan.strategy, path) || fallback

  defp objective_summary(objective) do
    %{
      id: objective.id,
      kind: objective.kind,
      label: objective.label,
      metric: objective.metric,
      target_value: decimal_to_float(objective.target_value),
      unit: objective.unit,
      priority: objective.priority
    }
  end

  defp plan_summary(plan) do
    %{
      id: plan.id,
      version: plan.version,
      status: plan.status,
      starts_on: plan.starts_on,
      review_on: plan.review_on,
      strategy: plan.strategy,
      rationale: plan.rationale,
      evidence: plan.evidence,
      persisted: not is_nil(plan.id)
    }
  end
end
