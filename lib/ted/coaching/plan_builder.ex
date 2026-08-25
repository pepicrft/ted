defmodule Ted.Coaching.PlanBuilder do
  @moduledoc "Creates an initial, reviewable strategy from explicit objectives."

  @evidence %{
    resistance_during_weight_loss: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12406911/",
    weight_loss_rate: "https://pubmed.ncbi.nlm.nih.gov/21558571/",
    protein: "https://pubmed.ncbi.nlm.nih.gov/28698222/",
    energy_surplus:
      "https://openrepository.aut.ac.nz/server/api/core/bitstreams/8dd49069-b58f-47ab-a7f4-ab1e78bc7245/content",
    autoregulation: "https://pubmed.ncbi.nlm.nih.gov/35038063/"
  }

  @spec build(map(), [map()], Decimal.t() | nil, pos_integer(), Date.t()) :: map()
  def build(profile, objectives, latest_weight, version, date) do
    primary = primary_objective(objectives)
    mode = if primary, do: primary.kind, else: "consistency"

    %{
      user_id: profile.user_id,
      version: version,
      status: "active",
      starts_on: date,
      review_on: Date.add(date, 14),
      objective_snapshot: Enum.map(objectives, &objective_snapshot/1),
      strategy: %{
        "mode" => mode,
        "nutrition" => nutrition_strategy(profile, latest_weight, mode),
        "training" => training_strategy(profile),
        "review" => %{
          "minimum_days" => 14,
          "minimum_check_ins" => 7,
          "maximum_energy_adjustment_percent" => 5,
          "change_one_major_variable_at_a_time" => true
        }
      },
      rationale: rationale(mode, latest_weight),
      evidence: evidence(mode),
      created_by: "ted"
    }
  end

  defp primary_objective(objectives), do: Enum.max_by(objectives, & &1.priority, fn -> nil end)

  defp objective_snapshot(objective) do
    %{
      "id" => objective.id,
      "kind" => objective.kind,
      "label" => objective.label,
      "metric" => objective.metric,
      "baseline_value" => decimal(objective.baseline_value),
      "target_value" => decimal(objective.target_value),
      "unit" => objective.unit,
      "target_date" => objective.target_date && Date.to_iso8601(objective.target_date),
      "priority" => objective.priority
    }
  end

  defp nutrition_strategy(profile, latest_weight, mode) do
    %{
      "energy_target_kcal" => profile.daily_energy_target_kcal,
      "protein_target_g" => protein_target(profile, latest_weight),
      "protein_basis" => protein_basis(profile, latest_weight),
      "target_weight_change_percent_per_week" => weight_change_range(mode, profile),
      "food_quality" =>
        "Build most meals around a protein-rich food, plants, and an amount of energy that supports the objective."
    }
  end

  defp protein_target(%{daily_protein_target_g: target}, _weight) when is_integer(target),
    do: target

  defp protein_target(_profile, %Decimal{} = weight),
    do: weight |> Decimal.mult(Decimal.new("1.6")) |> Decimal.round(0) |> Decimal.to_integer()

  defp protein_target(_profile, _weight), do: nil

  defp protein_basis(%{daily_protein_target_g: target}, _weight) when is_integer(target),
    do: "Person-defined target"

  defp protein_basis(_profile, %Decimal{}),
    do: "Starting estimate of 1.6 grams per kilogram of recorded body weight"

  defp protein_basis(_profile, _weight),
    do: "Waiting for a weight record or person-defined target"

  defp weight_change_range("fat_loss", _profile), do: [-0.75, -0.25]
  defp weight_change_range("body_recomposition", _profile), do: [-0.5, 0.0]
  defp weight_change_range("muscle_gain", %{experience_level: "beginner"}), do: [0.25, 0.5]
  defp weight_change_range("muscle_gain", %{experience_level: "intermediate"}), do: [0.15, 0.35]
  defp weight_change_range("muscle_gain", _profile), do: [0.1, 0.25]
  defp weight_change_range(_mode, _profile), do: [-0.25, 0.25]

  defp training_strategy(profile) do
    %{
      "days_per_week" => profile.training_days_per_week,
      "session_minutes" => profile.session_minutes,
      "equipment" => profile.equipment,
      "default_repetitions_in_reserve" => 2,
      "volume_multiplier" => 1.0,
      "progression" =>
        "Add a small amount of load after every prescribed repetition is completed with clean technique and about two repetitions still possible."
    }
  end

  defp rationale("fat_loss", nil),
    do: [
      "Establish a weight trend before changing energy intake.",
      "Keep resistance training in the plan to support strength and fat-free mass."
    ]

  defp rationale("fat_loss", _weight),
    do: [
      "Use a gradual weight-loss range rather than the fastest possible loss.",
      "Keep resistance training in the plan to support strength and fat-free mass."
    ]

  defp rationale("body_recomposition", _weight),
    do: [
      "Judge progress from weight trend, waist or another body-composition proxy, and strength together.",
      "Avoid an aggressive deficit while resistance training."
    ]

  defp rationale("muscle_gain", _weight),
    do: [
      "Use a conservative rate of gain because faster gain is more clearly associated with fat accumulation.",
      "Scale the target rate down as training experience increases."
    ]

  defp rationale(_mode, _weight),
    do: [
      "Build consistency first and review outcomes after enough observations.",
      "Adjust each session from readiness without rewriting the whole plan every day."
    ]

  defp evidence("fat_loss"),
    do: [@evidence.resistance_during_weight_loss, @evidence.weight_loss_rate, @evidence.protein]

  defp evidence("body_recomposition"),
    do: [@evidence.resistance_during_weight_loss, @evidence.protein]

  defp evidence("muscle_gain"),
    do: [@evidence.energy_surplus, @evidence.protein, @evidence.autoregulation]

  defp evidence(_mode), do: [@evidence.protein, @evidence.autoregulation]

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = value), do: Decimal.to_float(value)
end
