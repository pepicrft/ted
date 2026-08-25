defmodule Ted.Coaching.Reviewer do
  @moduledoc "Reviews one plan from trends, adherence, and recovery without overreacting to a day."

  @spec evaluate(map(), [map()], [map()], Date.t()) :: map()
  def evaluate(plan, check_ins, workouts, date) do
    observations = observations(plan, check_ins, workouts, date)

    cond do
      observations["pain_signal"] ->
        safety_hold(observations)

      observations["check_in_count"] < minimum_check_ins(plan) ->
        needs_data(observations, plan)

      observations["low_recovery"] ->
        recovery_adjustment(observations, plan)

      low_adherence?(observations) ->
        adherence_focus(observations)

      is_number(observations["weight_change_percent_per_week"]) ->
        weight_adjustment(observations, plan)

      true ->
        needs_data(observations, plan)
    end
  end

  defp observations(plan, check_ins, workouts, date) do
    energy_values = check_ins |> Enum.map(& &1.energy) |> Enum.reject(&is_nil/1)
    soreness_values = check_ins |> Enum.map(& &1.soreness) |> Enum.reject(&is_nil/1)
    adherence_values = check_ins |> Enum.map(& &1.nutrition_adherence) |> Enum.reject(&is_nil/1)

    %{
      "reviewed_on" => Date.to_iso8601(date),
      "plan_version" => plan.version,
      "check_in_count" => length(check_ins),
      "workout_count" => length(workouts),
      "average_energy" => average(energy_values),
      "average_soreness" => average(soreness_values),
      "average_nutrition_adherence" => average(adherence_values),
      "weight_change_percent_per_week" => weight_change_rate(check_ins),
      "pain_signal" => Enum.any?(check_ins, &((&1.pain || 0) >= 4)),
      "low_recovery" => low_recovery?(energy_values, soreness_values)
    }
  end

  defp safety_hold(observations) do
    %{
      status: "safety_hold",
      confidence: "high",
      observations: observations,
      decision: %{
        "summary" =>
          "Do not progress or intensify the plan while a meaningful pain signal is present.",
        "changes" => []
      },
      rationale: [
        "Pain is not treated as ordinary training soreness.",
        "Ask a qualified professional to assess persistent, severe, or worsening pain."
      ]
    }
  end

  defp needs_data(observations, plan) do
    %{
      status: "needs_data",
      confidence: "low",
      observations: observations,
      decision: %{
        "summary" => "Keep the current plan and collect more consistent observations.",
        "changes" => [],
        "needed_check_ins" => max(minimum_check_ins(plan) - observations["check_in_count"], 0)
      },
      rationale: ["A short or sparse record is too noisy for a useful plan-level adjustment."]
    }
  end

  defp recovery_adjustment(observations, plan) do
    current = get_in(plan.strategy, ["training", "volume_multiplier"]) || 1.0
    next = Float.round(max(current * 0.8, 0.6), 2)

    %{
      status: "adjusted",
      confidence: "moderate",
      observations: observations,
      decision: %{
        "summary" => "Reduce planned training volume temporarily and review recovery again.",
        "changes" => [
          %{
            "path" => ["training", "volume_multiplier"],
            "from" => current,
            "to" => next
          }
        ]
      },
      rationale: ["Repeated low energy or high soreness takes priority over progression."]
    }
  end

  defp adherence_focus(observations) do
    %{
      status: "no_change",
      confidence: "moderate",
      observations: observations,
      decision: %{
        "summary" => "Keep targets stable and make the current plan easier to follow.",
        "changes" => [],
        "focus" => "Choose one repeatable meal and schedule the next training session."
      },
      rationale: [
        "Changing the prescription before the current one is followed would confuse plan failure with adherence friction."
      ]
    }
  end

  defp weight_adjustment(observations, plan) do
    rate = observations["weight_change_percent_per_week"]
    [lower, upper] = get_in(plan.strategy, ["nutrition", "target_weight_change_percent_per_week"])

    cond do
      rate < lower -> energy_adjustment(observations, plan, :increase)
      rate > upper -> energy_adjustment(observations, plan, direction(plan))
      true -> on_track(observations, lower, upper)
    end
  end

  defp energy_adjustment(observations, plan, direction) do
    target = get_in(plan.strategy, ["nutrition", "energy_target_kcal"])

    if is_integer(target) do
      signed_change =
        if direction == :increase,
          do: min(round(target * 0.05), 200),
          else: -min(round(target * 0.05), 200)

      next = target + signed_change

      %{
        status: "adjusted",
        confidence: "moderate",
        observations: observations,
        decision: %{
          "summary" =>
            "Make one bounded energy adjustment and hold other major variables stable.",
          "changes" => [
            %{
              "path" => ["nutrition", "energy_target_kcal"],
              "from" => target,
              "to" => next
            }
          ]
        },
        rationale: ["The observed weight trend is outside the plan's target range."]
      }
    else
      %{
        status: "no_change",
        confidence: "low",
        observations: observations,
        decision: %{
          "summary" =>
            "The trend is outside range, but no energy target exists to adjust safely.",
          "changes" => [],
          "focus" => "Improve meal logging or set an initial energy target with the user."
        },
        rationale: ["Ted does not infer precise intake from incomplete meal logs."]
      }
    end
  end

  defp on_track(observations, lower, upper) do
    %{
      status: "no_change",
      confidence: "moderate",
      observations: observations,
      decision: %{
        "summary" => "The observed weight trend is within the plan range. Keep the plan stable.",
        "changes" => [],
        "target_range" => [lower, upper]
      },
      rationale: ["Avoid changing a plan that is moving toward its objective within tolerance."]
    }
  end

  defp direction(plan) do
    case plan.strategy["mode"] do
      mode when mode in ["fat_loss", "body_recomposition"] -> :decrease
      "muscle_gain" -> :increase
      _mode -> :decrease
    end
  end

  defp low_adherence?(%{"average_nutrition_adherence" => value}) when is_number(value),
    do: value < 3.0

  defp low_adherence?(_observations), do: false

  defp low_recovery?(energy, soreness) do
    (length(energy) >= 3 and average(Enum.take(energy, -3)) < 2.5) or
      (length(soreness) >= 3 and average(Enum.take(soreness, -3)) > 4.0)
  end

  defp weight_change_rate(check_ins) do
    weighted = Enum.filter(check_ins, &match?(%Decimal{}, &1.weight_kg))

    if length(weighted) >= 7 do
      first_group = Enum.take(weighted, 3)
      last_group = Enum.take(weighted, -3)
      first = first_group |> Enum.map(&Decimal.to_float(&1.weight_kg)) |> average()
      last = last_group |> Enum.map(&Decimal.to_float(&1.weight_kg)) |> average()
      days = Date.diff(List.last(last_group).date, hd(first_group).date)

      if days >= 7 and first > 0,
        do: Float.round((last - first) / first * 100 * 7 / days, 2),
        else: nil
    else
      nil
    end
  end

  defp minimum_check_ins(plan),
    do: get_in(plan.strategy, ["review", "minimum_check_ins"]) || 7

  defp average([]), do: nil
  defp average(values), do: (Enum.sum(values) / length(values)) |> Float.round(2)
end
