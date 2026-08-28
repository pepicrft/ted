defmodule Ted.CoachingTest do
  use Ted.DataCase, async: true

  alias Ted.Accounts
  alias Ted.Coaching

  test "builds a versioned plan around explicit objectives and keeps people isolated", %{
    repo: repo
  } do
    first = user!(repo, "first@example.test")
    second = user!(repo, "second@example.test")

    assert {:ok, _profile} =
             Coaching.update_profile(
               first.id,
               %{
                 "primary_goal" => "fat_loss",
                 "experience_level" => "intermediate",
                 "training_days_per_week" => 3,
                 "daily_energy_target_kcal" => 2_200,
                 "daily_protein_target_g" => 150
               },
               repo
             )

    assert {:ok, objective} =
             Coaching.set_objective(
               first.id,
               %{
                 "kind" => "fat_loss",
                 "label" => "Reach 78 kilograms gradually",
                 "metric" => "body_weight_kg",
                 "target_value" => 78,
                 "unit" => "kg",
                 "priority" => 5
               },
               repo
             )

    assert objective.kind == "fat_loss"
    assert {:ok, plan} = Coaching.build_plan(first.id, ~D[2026-08-01], repo)
    assert plan.version == 1
    assert plan.strategy["mode"] == "fat_loss"
    assert plan.review_on == ~D[2026-08-15]
    assert plan.evidence != []

    assert {:ok, today} = Coaching.today_plan(first.id, ~D[2026-08-02], repo)
    assert today.active_plan.version == 1
    assert [%{label: "Reach 78 kilograms gradually"}] = today.objectives

    assert {:ok, []} = Coaching.list_objectives(second.id, repo)
    assert {:error, :not_found} = Coaching.active_plan(second.id, repo)
  end

  test "a review makes one bounded adjustment from a sufficient trend", %{repo: repo} do
    user = user!(repo, "review@example.test")

    assert {:ok, _profile} =
             Coaching.update_profile(
               user.id,
               %{
                 "primary_goal" => "fat_loss",
                 "daily_energy_target_kcal" => 2_000,
                 "daily_protein_target_g" => 145
               },
               repo
             )

    assert {:ok, _objective} =
             Coaching.set_objective(
               user.id,
               %{"kind" => "fat_loss", "label" => "Reduce weight gradually", "priority" => 5},
               repo
             )

    assert {:ok, plan} = Coaching.build_plan(user.id, ~D[2026-08-01], repo)

    Enum.each(0..8, fn day ->
      assert {:ok, _check_in} =
               Coaching.record_check_in(
                 user.id,
                 %{
                   "date" => Date.add(~D[2026-08-01], day),
                   "weight_kg" => 80 + day * 0.2,
                   "energy" => 4,
                   "soreness" => 2,
                   "nutrition_adherence" => 4
                 },
                 repo
               )
    end)

    assert {:ok, review} = Coaching.review_plan(user.id, ~D[2026-08-09], repo)
    assert review.status == "adjusted"
    assert review.confidence == "moderate"
    assert length(review.decision["changes"]) == 1
    assert review.next_plan.version == plan.version + 1
    assert review.next_plan.strategy["nutrition"]["energy_target_kcal"] == 1_900
  end

  test "recommends concrete vegetarian meals without inventing missing intake", %{repo: repo} do
    user = user!(repo, "vegetarian@example.test")

    assert {:ok, _profile} =
             Coaching.update_profile(
               user.id,
               %{
                 "primary_goal" => "fat_loss",
                 "dietary_preferences" => ["vegetarian"],
                 "daily_energy_target_kcal" => 2_100,
                 "daily_protein_target_g" => 140
               },
               repo
             )

    assert {:ok, _objective} =
             Coaching.set_objective(
               user.id,
               %{"kind" => "fat_loss", "label" => "Reduce weight gradually", "priority" => 5},
               repo
             )

    assert {:ok, _plan} = Coaching.build_plan(user.id, ~D[2026-08-16], repo)

    assert {:ok, _breakfast} =
             Coaching.log_meal(
               user.id,
               %{
                 "occurred_at" => ~U[2026-08-16 08:00:00Z],
                 "description" => "Breakfast away from home, portions unknown"
               },
               repo
             )

    assert {:ok, _lunch} =
             Coaching.log_meal(
               user.id,
               %{
                 "occurred_at" => ~U[2026-08-16 12:30:00Z],
                 "description" => "Estimated lentil lunch",
                 "energy_kcal" => 720,
                 "protein_g" => 32
               },
               repo
             )

    assert {:ok, recommendation} =
             Coaching.recommend_meal(
               user.id,
               %{
                 "date" => "2026-08-16",
                 "meal_type" => "dinner",
                 "time_available_minutes" => 25,
                 "avoid" => ["soy", "dairy"]
               },
               repo
             )

    assert recommendation.dietary_pattern == "vegetarian"
    assert recommendation.targets.energy_logged_kcal == 720
    assert recommendation.targets.energy_unquantified_meals == 1
    assert recommendation.targets.energy_remaining_from_logged_estimates_kcal == nil
    assert recommendation.targets.energy_status == "incomplete_log"
    assert recommendation.targets.protein_logged_g == 32.0
    assert recommendation.targets.protein_unquantified_meals == 1
    assert recommendation.targets.protein_remaining_from_logged_estimates_g == nil
    assert recommendation.targets.suggested_protein_contribution_g == 35

    assert Enum.map(recommendation.suggestions, & &1.name) == [
             "Quick lentil and quinoa bowl",
             "Lentil pasta with tomato and greens",
             "Three-bean chili with potato"
           ]

    refute inspect(recommendation.suggestions) =~ "tofu"
    refute inspect(recommendation.suggestions) =~ "yogurt"

    assert Enum.any?(
             recommendation.evidence,
             &(&1.url == "https://pubmed.ncbi.nlm.nih.gov/33599941/")
           )

    assert Enum.any?(
             recommendation.evidence,
             &(&1.url == "https://pubmed.ncbi.nlm.nih.gov/39813010/")
           )

    assert {:ok, today} = Coaching.today_plan(user.id, ~D[2026-08-16], repo)
    assert today.nutrition.next_meal.dietary_pattern == "vegetarian"
    assert today.nutrition.next_meal.suggestions != []
    assert today.nutrition.guidance =~ "concrete option"
  end

  test "keeps named workout templates versioned and isolated by person", %{repo: repo} do
    first = user!(repo, "templates-first@example.test")
    second = user!(repo, "templates-second@example.test")

    attributes = workout_template_attributes()

    assert {:ok, template} = Coaching.save_workout_template(first.id, attributes, repo)
    assert template.name == "Full-body strength A"
    assert template.version == 1
    assert template.image_url == "/assets/workouts/full-body-strength-a.png"

    assert [
             %{
               "name" => "Barbell squat",
               "rest_seconds" => 150,
               "image_url" => "/assets/exercises/barbell-squat.png",
               "image_alt" => "Original reference illustration of a barbell back squat.",
               "video_url" => "https://www.youtube.com/watch?v=8PMjqgR8Wa8"
             }
           ] = template.movements

    assert {:ok, [listed]} = Coaching.list_workout_templates(first.id, repo)
    assert listed.id == template.id
    assert {:ok, []} = Coaching.list_workout_templates(second.id, repo)
    assert {:error, :not_found} = Coaching.get_workout_template(second.id, template.id, repo)

    assert {:ok, prepared} = Coaching.prepare_workout(first.id, template.id, repo)
    assert prepared.template.id == template.id
    assert prepared.workout.workout_template_id == template.id
    assert prepared.workout.workout_template_version == 1
    assert prepared.workout.movements == template.movements
    assert prepared.visual_guidance =~ "recognition cue"

    assert {:ok, refined} =
             Coaching.save_workout_template(
               first.id,
               Map.merge(attributes, %{
                 "id" => template.id,
                 "name" => "Full-body strength A, refined"
               }),
               repo
             )

    assert refined.version == 2

    assert {:ok, completed} =
             Coaching.log_workout(
               first.id,
               %{
                 "name" => refined.name,
                 "movements" => refined.movements,
                 "workout_template_id" => refined.id,
                 "workout_template_version" => refined.version
               },
               repo
             )

    assert completed.workout_template_id == refined.id
    assert completed.workout_template_version == 2

    assert {:error, :not_found} =
             Coaching.save_workout_template(
               second.id,
               Map.put(attributes, "id", refined.id),
               repo
             )

    attributes_without_video =
      Map.update!(attributes, "movements", fn [movement] ->
        [Map.delete(movement, "video_url")]
      end)

    assert {:error, _changeset} =
             Coaching.save_workout_template(first.id, attributes_without_video, repo)
  end

  defp workout_template_attributes do
    %{
      "name" => "Full-body strength A",
      "description" => "A configurable, repeatable strength session.",
      "estimated_duration_minutes" => 50,
      "image_url" => "/assets/workouts/full-body-strength-a.png",
      "image_alt" =>
        "Three-panel reference illustration showing a barbell squat, a barbell bench press, and a bent-over barbell row.",
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
  end

  defp user!(repo, email) do
    assert {:ok, user} = Accounts.create_user(%{"email" => email, "name" => email}, repo)
    user
  end
end
