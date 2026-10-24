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

  test "follows the agreed template order across weeks and snapshots prescriptions", %{repo: repo} do
    user = user!(repo, "planned-workouts@example.test")
    other = user!(repo, "other-workouts@example.test")
    date = Date.utc_today()
    attrs = workout_template_attributes()
    assert {:ok, first} = Coaching.save_workout_template(user.id, attrs, repo)

    second_attrs =
      attrs
      |> Map.put("name", "Second session")
      |> Map.update!("movements", fn [movement] ->
        [Map.merge(movement, %{"id" => "second-squat", "sets" => 2})]
      end)

    assert {:ok, second} = Coaching.save_workout_template(user.id, second_attrs, repo)
    assert {:ok, other_template} = Coaching.save_workout_template(other.id, attrs, repo)

    assert {:ok, unconfigured} = Coaching.today_plan(user.id, date, repo)
    assert unconfigured.training.kind == "needs_configuration"
    refute Map.has_key?(unconfigured.training, :movements)
    assert {:error, :workout_not_ready} = Coaching.start_workout(user.id, %{}, repo)
    assert {:error, :not_found} = Coaching.build_plan(user.id, date, repo, [other_template.id])
    assert {:error, :invalid_arguments} = Coaching.build_plan(user.id, date, repo, ["invalid"])

    assert {:ok, plan} = Coaching.build_plan(user.id, date, repo, [second.id, first.id])

    assert {:ok, _edited} =
             Coaching.save_workout_template(
               user.id,
               Map.merge(second_attrs, %{
                 "id" => second.id,
                 "name" => "Changed after planning",
                 "movements" => Enum.map(second_attrs["movements"], &Map.put(&1, "sets", 7))
               }),
               repo
             )

    assert {:ok, today} = Coaching.today_plan(user.id, date, repo)
    assert today.training.title == "Second session"
    assert today.training.movements == second.movements
    assert today.training.template["version"] == 1

    assert {:ok, workout} = Coaching.start_workout(user.id, %{}, repo)
    assert workout.plan_id == plan.id
    assert workout.movements == second.movements
    assert workout.progress.total_sets == 2
    assert {:ok, resumed} = Coaching.start_workout(user.id, %{}, repo)
    assert resumed.id == workout.id

    set = %{
      "id" => workout.id,
      "movement_id" => "second-squat",
      "set_number" => 2,
      "repetitions" => 4,
      "load_kg" => 62.5
    }

    assert {:ok, partial} = Coaching.record_workout_set(user.id, set, repo)
    assert partial.progress.completed_sets == 1
    assert partial.progress.remaining_sets == 1
    assert partial.progress.next_set.set_number == 1
    assert {:ok, retried} = Coaching.record_workout_set(user.id, set, repo)
    assert retried.completed_sets == partial.completed_sets

    assert {:ok, corrected} =
             Coaching.record_workout_set(user.id, Map.put(set, "repetitions", 6), repo)

    assert [%{"repetitions" => 6, "load_kg" => 62.5}] = corrected.completed_sets
    assert corrected.progress.completed_sets == 1

    assert {:error, :workout_incomplete} =
             Coaching.finish_workout(
               user.id,
               %{"id" => workout.id, "status" => "completed"},
               repo
             )

    assert {:error, :invalid_arguments} =
             Coaching.record_workout_set(
               user.id,
               Map.put(set, "movement_id", "invented-exercise"),
               repo
             )

    assert {:error, :invalid_arguments} =
             Coaching.record_workout_set(user.id, Map.put(set, "set_number", 3), repo)

    assert {:error, :not_found} = Coaching.get_workout(other.id, workout.id, repo)
    assert {:error, :not_found} = Coaching.record_workout_set(other.id, set, repo)

    assert {:error, :not_found} =
             Coaching.finish_workout(
               other.id,
               %{"id" => workout.id, "status" => "cancelled"},
               repo
             )

    assert {:ok, current} = Coaching.get_current_workout(user.id, repo)
    assert current.completed_sets == corrected.completed_sets
    assert {:ok, daily} = Coaching.today_plan(user.id, date, repo)
    assert daily.training.kind == "in_progress"
    assert daily.current_workout.id == workout.id
    assert {:ok, progress} = Coaching.progress(user.id, 30, repo)
    assert progress.summary.workouts_completed == 0
    assert progress.summary.workouts_in_progress == 1
    assert {:ok, review} = Coaching.review_plan(user.id, date, repo)
    assert review.observations["workout_count"] == 0

    assert {:ok, all_sets} =
             Coaching.record_workout_set(user.id, Map.put(set, "set_number", 1), repo)

    assert all_sets.status == "in_progress"
    assert all_sets.progress.next_set == nil

    assert {:ok, completed} =
             Coaching.finish_workout(
               user.id,
               %{"id" => workout.id, "status" => "completed", "duration_minutes" => 37},
               repo
             )

    assert completed.duration_minutes == 37
    assert completed.completed_at != nil

    assert {:ok, ^completed} =
             Coaching.finish_workout(
               user.id,
               %{"id" => workout.id, "status" => "completed"},
               repo
             )

    assert {:error, :workout_not_in_progress} = Coaching.record_workout_set(user.id, set, repo)
    assert {:error, :not_found} = Coaching.get_current_workout(user.id, repo)
    assert {:ok, progress} = Coaching.progress(user.id, 30, repo)
    assert progress.summary.workouts_completed == 1

    assert {:ok, later} = Coaching.today_plan(user.id, Date.add(date, 10), repo)
    assert later.training.template["id"] == first.id
    assert {:ok, rebuilt} = Coaching.build_plan(user.id, date, repo)

    assert rebuilt.strategy["training"]["workout_templates"] ==
             plan.strategy["training"]["workout_templates"]
  end

  test "persists pain signals, keeps cancelled progress, and blocks further progression", %{
    repo: repo
  } do
    user = user!(repo, "workout-pain@example.test")
    date = Date.utc_today()

    assert {:ok, template} =
             Coaching.save_workout_template(user.id, workout_template_attributes(), repo)

    assert {:ok, _plan} = Coaching.build_plan(user.id, date, repo, [template.id])
    assert {:ok, workout} = Coaching.start_workout(user.id, %{}, repo)

    set = %{
      "id" => workout.id,
      "movement_id" => "back-squat",
      "set_number" => 1,
      "repetitions" => 5,
      "pain" => 3
    }

    assert {:ok, below_threshold} = Coaching.record_workout_set(user.id, set, repo)
    refute below_threshold.progress.safety_hold
    assert below_threshold.progress.next_set.set_number == 2

    painful_set = Map.merge(set, %{"set_number" => 2, "repetitions" => 2, "pain" => 4})
    assert {:ok, held} = Coaching.record_workout_set(user.id, painful_set, repo)
    assert held.progress.safety_hold
    assert held.progress.next_set == nil
    assert {:ok, daily} = Coaching.today_plan(user.id, date, repo)
    assert daily.training.kind == "safety_hold"

    assert {:error, :safety_hold} =
             Coaching.record_workout_set(user.id, Map.put(set, "set_number", 3), repo)

    assert {:error, :safety_hold} =
             Coaching.finish_workout(
               user.id,
               %{"id" => workout.id, "status" => "completed"},
               repo
             )

    assert {:ok, cancelled} =
             Coaching.finish_workout(
               user.id,
               %{"id" => workout.id, "status" => "cancelled"},
               repo
             )

    assert length(cancelled.completed_sets) == 2
    assert cancelled.progress.remaining_sets == 1
    assert {:ok, history} = Coaching.get_workout(user.id, workout.id, repo)
    assert history.status == "cancelled"
    assert {:error, :safety_hold} = Coaching.start_workout(user.id, %{}, repo)
    assert {:ok, review} = Coaching.review_plan(user.id, date, repo)
    assert review.status == "safety_hold"
    assert review.observations["pain_signal"]
    assert review.observations["workout_count"] == 0
    assert {:ok, progress} = Coaching.progress(user.id, 30, repo)
    assert progress.summary.workouts_completed == 0
    assert progress.summary.workouts_in_progress == 0
  end

  test "applies reviewed volume to the saved movements without rewriting a live session", %{
    repo: repo
  } do
    user = user!(repo, "review-workout@example.test")
    date = Date.utc_today()

    attrs =
      Map.update!(workout_template_attributes(), "movements", fn [movement] ->
        [movement, Map.merge(movement, %{"id" => "second-movement", "sets" => 5})]
      end)

    assert {:ok, template} = Coaching.save_workout_template(user.id, attrs, repo)
    assert {:ok, _plan} = Coaching.build_plan(user.id, Date.add(date, -14), repo, [template.id])
    assert {:ok, workout} = Coaching.start_workout(user.id, %{}, repo)

    for number <- 1..3 do
      assert {:ok, _partial} =
               Coaching.record_workout_set(
                 user.id,
                 %{
                   "id" => workout.id,
                   "movement_id" => "back-squat",
                   "set_number" => number,
                   "repetitions" => 5
                 },
                 repo
               )
    end

    assert {:ok, transitioned} = Coaching.get_current_workout(user.id, repo)
    assert transitioned.progress.next_set.movement["id"] == "second-movement"
    assert transitioned.progress.next_set.set_number == 1
    assert transitioned.progress.remaining_sets == 5

    for day <- -6..0 do
      assert {:ok, _check_in} =
               Coaching.record_check_in(
                 user.id,
                 %{
                   "date" => Date.add(date, day),
                   "energy" => 1,
                   "soreness" => 5
                 },
                 repo
               )
    end

    assert {:ok, review} = Coaching.review_plan(user.id, date, repo)
    assert review.status == "adjusted"
    assert review.next_plan.strategy["training"]["volume_multiplier"] == 0.8
    assert {:ok, live} = Coaching.get_current_workout(user.id, repo)
    assert live.movements == workout.movements
    assert live.progress.total_sets == 8

    assert {:ok, _cancelled} =
             Coaching.finish_workout(
               user.id,
               %{"id" => workout.id, "status" => "cancelled"},
               repo
             )

    assert {:ok, next} = Coaching.today_plan(user.id, Date.add(date, 1), repo)
    assert Enum.map(next.training.movements, & &1["sets"]) == [2, 4]
    assert Enum.map(next.training.movements, & &1["id"]) == ["back-squat", "second-movement"]
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
