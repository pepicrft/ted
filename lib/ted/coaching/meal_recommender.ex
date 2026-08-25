defmodule Ted.Coaching.MealRecommender do
  @moduledoc "Builds a concrete, preference-aware meal recommendation from recorded facts."

  @daily_protein_evidence %{
    title: "Morton and colleagues, 2018",
    claim:
      "Total daily protein supports resistance-training adaptations, with the modeled benefit leveling near 1.62 grams per kilogram per day.",
    url: "https://pubmed.ncbi.nlm.nih.gov/28698222/",
    limitation:
      "The analysis pooled varied supplementation trials and does not establish one ideal amount for every person or meal."
  }

  @distribution_evidence %{
    title: "Jespersen and Agergaard, 2021",
    claim: "A more even protein distribution was associated with muscle mass in some studies.",
    url: "https://pubmed.ncbi.nlm.nih.gov/33550490/",
    limitation:
      "The review found insufficient evidence for firm conclusions about strength or protein turnover."
  }

  @plant_trial_evidence %{
    title: "Hevia-Larraín and colleagues, 2021",
    claim:
      "Protein-matched vegan and omnivorous diets supported similar strength and muscle gains during 12 weeks of resistance training.",
    url: "https://pubmed.ncbi.nlm.nih.gov/33599941/",
    limitation:
      "The trial involved 38 healthy, untrained young men and used soy or whey supplementation, so it does not cover every population or plant-based diet."
  }

  @plant_review_evidence %{
    title: "Reynolds and colleagues, 2025",
    claim:
      "Across randomized trials, soy and milk did not differ for muscle mass; plant and animal protein did not differ for strength or physical performance.",
    url: "https://pubmed.ncbi.nlm.nih.gov/39813010/",
    limitation:
      "Animal protein had a small pooled advantage over non-soy plant proteins for muscle mass, and the authors called for research across more plant proteins and diets."
  }

  @templates [
    %{
      id: "soy_yogurt_oat_bowl",
      name: "Soy yogurt, oat, and berry bowl",
      diets: ~w(vegan vegetarian pescatarian omnivore),
      meal_types: ~w(breakfast snack any),
      minutes: 5,
      tags: ~w(soy gluten),
      ingredients:
        "Unsweetened soy yogurt, oats, berries, seeds, and an optional measured scoop of soy or pea protein."
    },
    %{
      id: "tofu_scramble",
      name: "Tofu scramble with toast and fruit",
      diets: ~w(vegan vegetarian pescatarian omnivore),
      meal_types: ~w(breakfast lunch any),
      minutes: 15,
      tags: ~w(soy gluten),
      ingredients: "Crumbled tofu, mixed vegetables, whole-grain toast, and a piece of fruit."
    },
    %{
      id: "lentil_quinoa_bowl",
      name: "Quick lentil and quinoa bowl",
      diets: ~w(vegan vegetarian pescatarian omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 5,
      tags: ~w(legumes),
      ingredients:
        "A measured lentil pouch, pre-cooked quinoa, bagged salad, chopped vegetables, and lemon dressing."
    },
    %{
      id: "tofu_edamame_bowl",
      name: "Tofu and edamame grain bowl",
      diets: ~w(vegan vegetarian pescatarian omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 20,
      tags: ~w(soy),
      ingredients: "Tofu, edamame, rice or quinoa, colorful vegetables, and a simple dressing."
    },
    %{
      id: "lentil_pasta",
      name: "Lentil pasta with tomato and greens",
      diets: ~w(vegan vegetarian pescatarian omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 20,
      tags: ~w(legumes),
      ingredients:
        "Lentil pasta, tomato sauce, spinach or another green vegetable, and nutritional yeast if wanted."
    },
    %{
      id: "three_bean_chili",
      name: "Three-bean chili with potato",
      diets: ~w(vegan vegetarian pescatarian omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 25,
      tags: ~w(legumes),
      ingredients: "Mixed beans, tomatoes, peppers, spices, and a baked or microwaved potato."
    },
    %{
      id: "pea_smoothie",
      name: "Fruit and pea-protein smoothie",
      diets: ~w(vegan vegetarian pescatarian omnivore),
      meal_types: ~w(breakfast snack any),
      minutes: 5,
      tags: [],
      ingredients:
        "A measured pea-protein serving, fruit, oats, water or a compatible fortified drink, and ice."
    },
    %{
      id: "greek_yogurt_bowl",
      name: "Greek-style yogurt, oat, and fruit bowl",
      diets: ~w(vegetarian pescatarian omnivore),
      meal_types: ~w(breakfast snack any),
      minutes: 5,
      tags: ~w(dairy gluten),
      ingredients: "Greek-style yogurt, oats, fruit, and seeds."
    },
    %{
      id: "cottage_cheese_plate",
      name: "Cottage cheese, toast, and tomato plate",
      diets: ~w(vegetarian pescatarian omnivore),
      meal_types: ~w(breakfast lunch snack any),
      minutes: 5,
      tags: ~w(dairy gluten),
      ingredients: "Cottage cheese, whole-grain toast, tomatoes, cucumber, and fruit."
    },
    %{
      id: "egg_bean_skillet",
      name: "Egg, bean, and potato skillet",
      diets: ~w(vegetarian pescatarian omnivore),
      meal_types: ~w(breakfast lunch dinner any),
      minutes: 20,
      tags: ~w(egg legumes),
      ingredients: "Eggs, beans, potatoes, peppers, and leafy greens."
    },
    %{
      id: "salmon_potato_plate",
      name: "Salmon, potato, and vegetable plate",
      diets: ~w(pescatarian omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 25,
      tags: ~w(fish),
      ingredients: "Salmon, potatoes, and two vegetables you enjoy."
    },
    %{
      id: "tuna_bean_salad",
      name: "Tuna and bean salad",
      diets: ~w(pescatarian omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 5,
      tags: ~w(fish legumes),
      ingredients: "Tuna, white beans, salad leaves, tomatoes, and lemon dressing."
    },
    %{
      id: "chicken_rice_bowl",
      name: "Chicken, rice, and vegetable bowl",
      diets: ~w(omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 20,
      tags: ~w(meat),
      ingredients: "Chicken, rice, mixed vegetables, and a simple sauce."
    },
    %{
      id: "turkey_bean_wrap",
      name: "Turkey and bean wrap",
      diets: ~w(omnivore),
      meal_types: ~w(lunch dinner any),
      minutes: 10,
      tags: ~w(meat gluten legumes),
      ingredients: "Turkey, beans, a whole-grain wrap, salad vegetables, and salsa."
    }
  ]

  @spec build(map(), map()) :: map()
  def build(facts, options \\ %{}) when is_map(facts) and is_map(options) do
    profile = facts.profile
    meals = facts.meals
    meal_type = Map.get(options, "meal_type", "any")
    time_available = Map.get(options, "time_available_minutes")
    requested_avoid = normalize_list(Map.get(options, "avoid", []))
    preferences = normalize_list(profile.dietary_preferences)
    dietary_pattern = dietary_pattern(preferences)
    constraints = known_constraints(preferences, requested_avoid)
    protein = protein_status(profile, meals, facts.plan, meal_type)
    energy = energy_status(profile, meals, facts.plan)

    suggestions =
      @templates
      |> Enum.filter(fn template ->
        compatible_diet?(template, dietary_pattern) and
          compatible_meal_type?(template, meal_type) and
          compatible_time?(template, time_available)
      end)
      |> Enum.reject(&excluded?(&1, constraints, requested_avoid))
      |> Enum.take(3)
      |> Enum.map(&suggestion(&1, protein.suggested_contribution_g, profile.primary_goal))

    %{
      date: facts.date,
      meal_type: meal_type,
      dietary_pattern: dietary_pattern,
      preferences_applied: preferences,
      avoided_ingredients: Enum.uniq(constraints ++ requested_avoid),
      guidance: guidance(suggestions, protein),
      targets: %{
        daily_energy_target_kcal: energy.target,
        energy_logged_kcal: energy.logged,
        energy_unquantified_meals: energy.unquantified_meals,
        energy_remaining_from_logged_estimates_kcal: energy.remaining,
        energy_status: energy.status,
        daily_protein_target_g: protein.target,
        protein_logged_g: protein.logged,
        protein_unquantified_meals: protein.unquantified_meals,
        protein_remaining_from_logged_estimates_g: protein.remaining,
        suggested_protein_contribution_g: protein.suggested_contribution_g,
        suggested_protein_basis: protein.suggested_basis
      },
      suggestions: suggestions,
      evidence: evidence(dietary_pattern),
      requires_clarification: suggestions == [],
      safety: [
        "Do not use a suggestion containing an allergen or medically restricted ingredient.",
        "Use package, recipe, or measured values when tracking. Ted does not present template nutrition as measured intake.",
        "Ask a qualified professional before using higher-protein guidance with kidney disease, pregnancy, disordered eating, or another relevant health condition."
      ]
    }
  end

  defp protein_status(profile, meals, plan, meal_type) do
    target = plan_value(plan, ["nutrition", "protein_target_g"], profile.daily_protein_target_g)
    quantified = Enum.reject(meals, &is_nil(&1.protein_g))
    logged = quantified |> Enum.reduce(0.0, &(decimal_to_float(&1.protein_g) + &2)) |> round_one()
    unquantified = length(meals) - length(quantified)

    remaining =
      if is_number(target) and unquantified == 0,
        do: max(round_one(target - logged), 0.0),
        else: nil

    {suggested, basis} = protein_contribution(target, remaining, unquantified, meal_type)

    %{
      target: target,
      logged: logged,
      unquantified_meals: unquantified,
      remaining: remaining,
      suggested_contribution_g: suggested,
      suggested_basis: basis
    }
  end

  defp energy_status(profile, meals, plan) do
    target =
      plan_value(plan, ["nutrition", "energy_target_kcal"], profile.daily_energy_target_kcal)

    quantified = Enum.reject(meals, &is_nil(&1.energy_kcal))
    logged = Enum.reduce(quantified, 0, &(&1.energy_kcal + &2))
    unquantified = length(meals) - length(quantified)

    remaining =
      if is_integer(target) and unquantified == 0, do: max(target - logged, 0), else: nil

    status =
      cond do
        is_nil(target) -> "no_daily_target"
        unquantified > 0 -> "incomplete_log"
        true -> "based_on_recorded_estimates"
      end

    %{
      target: target,
      logged: logged,
      unquantified_meals: unquantified,
      remaining: remaining,
      status: status
    }
  end

  defp protein_contribution(nil, _remaining, _unquantified, _meal_type) do
    {nil, "No daily protein target is available, so Ted does not invent a meal target."}
  end

  defp protein_contribution(_target, remaining, 0, _meal_type) when remaining <= 0 do
    {nil,
     "Recorded estimates already meet the daily target; this is not a reason to skip a needed meal."}
  end

  defp protein_contribution(_target, remaining, 0, meal_type) do
    opportunities = remaining_opportunities(meal_type)
    contribution = remaining |> Kernel./(opportunities) |> round() |> clamp(20, 45)

    {contribution,
     "A practical share of the gap in recorded estimates, bounded for usability rather than presented as a physiological optimum."}
  end

  defp protein_contribution(target, _remaining, _unquantified, _meal_type) do
    contribution = target |> Kernel./(4) |> round() |> clamp(20, 45)

    {contribution,
     "One practical quarter of the daily target because at least one meal lacks a protein estimate; this is not a claim about the exact remaining intake."}
  end

  defp suggestion(template, protein_contribution, goal) do
    %{
      id: template.id,
      name: template.name,
      ready_in_minutes: template.minutes,
      ingredients: template.ingredients,
      portion_guidance: portion_guidance(protein_contribution),
      objective_adjustment: objective_adjustment(goal)
    }
  end

  defp portion_guidance(nil) do
    "Choose a satisfying portion and use the package or recipe if you want to record nutrition values."
  end

  defp portion_guidance(protein_contribution) do
    "Adjust the protein-food portion using its package or recipe so the meal contributes about #{protein_contribution} grams of protein. Treat that as a planning target, not a measured result."
  end

  defp objective_adjustment("fat_loss") do
    "Keep the protein food prominent, include fruit or vegetables, and size energy-dense additions to the active plan and comfortable hunger."
  end

  defp objective_adjustment("muscle_gain") do
    "Include a useful carbohydrate source and increase portions gradually only when the plan review supports it."
  end

  defp objective_adjustment(_goal) do
    "Include a protein food, plants, and enough carbohydrate-rich food to support the planned training."
  end

  defp guidance([], _protein) do
    "I cannot find a template that satisfies every recorded constraint. Tell me which ingredients are safe and available."
  end

  defp guidance([first | _rest], %{suggested_contribution_g: nil}) do
    "A concrete option is #{first.name}. Choose from the compatible alternatives and record only values you can support."
  end

  defp guidance([first | _rest], protein) do
    "A concrete option is #{first.name}. Aim for about #{protein.suggested_contribution_g} grams of protein using package or recipe values, then choose another compatible option if that fits your appetite or schedule better."
  end

  defp evidence(pattern) when pattern in ["vegan", "vegetarian"] do
    [
      @daily_protein_evidence,
      @distribution_evidence,
      @plant_trial_evidence,
      @plant_review_evidence
    ]
  end

  defp evidence(_pattern), do: [@daily_protein_evidence, @distribution_evidence]

  defp compatible_diet?(template, pattern), do: pattern in template.diets

  defp compatible_meal_type?(_template, "any"), do: true
  defp compatible_meal_type?(template, meal_type), do: meal_type in template.meal_types

  defp compatible_time?(_template, nil), do: true
  defp compatible_time?(template, minutes), do: template.minutes <= minutes

  defp excluded?(template, constraints, requested_avoid) do
    search = normalize("#{template.name} #{template.ingredients}")

    Enum.any?(constraints, &(&1 in template.tags)) or
      Enum.any?(requested_avoid, &String.contains?(search, &1))
  end

  defp dietary_pattern(preferences) do
    cond do
      Enum.any?(preferences, &String.contains?(&1, "vegan")) -> "vegan"
      Enum.any?(preferences, &String.contains?(&1, "vegetarian")) -> "vegetarian"
      Enum.any?(preferences, &String.contains?(&1, "pescatarian")) -> "pescatarian"
      true -> "omnivore"
    end
  end

  defp known_constraints(preferences, requested_avoid) do
    (preferences ++ requested_avoid)
    |> Enum.flat_map(fn value ->
      Enum.filter(~w(soy dairy egg gluten nuts fish shellfish meat legumes), fn tag ->
        avoidance?(value, tag)
      end)
    end)
    |> Enum.uniq()
  end

  defp avoidance?(value, tag) do
    value == tag or
      Enum.any?(
        ["#{tag}-free", "#{tag} free", "#{tag} allergy", "avoid #{tag}", "no #{tag}"],
        &String.contains?(value, &1)
      )
  end

  defp normalize_list(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_list(_values), do: []

  defp normalize(value) do
    value
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end

  defp remaining_opportunities("breakfast"), do: 4
  defp remaining_opportunities("lunch"), do: 3
  defp remaining_opportunities("dinner"), do: 2
  defp remaining_opportunities("snack"), do: 2
  defp remaining_opportunities(_meal_type), do: 3

  defp decimal_to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp decimal_to_float(value) when is_number(value), do: value / 1

  defp round_one(value), do: Float.round(value / 1, 1)
  defp clamp(value, minimum, maximum), do: value |> max(minimum) |> min(maximum)

  defp plan_value(nil, _path, fallback), do: fallback
  defp plan_value(plan, path, fallback), do: get_in(plan.strategy, path) || fallback
end
