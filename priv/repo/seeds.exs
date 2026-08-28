import Ecto.Query

alias Ted.Accounts.User
alias Ted.Coaching
alias Ted.Coaching.{CheckIn, Meal, Objective, Plan, Profile, Workout, WorkoutTemplate}
alias Ted.Repo

local_id = "00000000-0000-0000-0000-000000000001"
alex_id = "00000000-0000-0000-0000-000000000002"

now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
today = Date.utc_today()

ensure_template_guidance = fn user_id, template_name, guidance_by_movement_id ->
  template =
    Repo.one(
      from(template in WorkoutTemplate,
        where: template.user_id == ^user_id and template.name == ^template_name
      )
    )

  if template do
    movements =
      Enum.map(template.movements, fn movement ->
        case guidance_by_movement_id[movement["id"]] do
          guidance when is_map(guidance) ->
            Enum.reduce(guidance, movement, fn {key, value}, updated_movement ->
              case updated_movement[key] do
                existing_value when is_binary(existing_value) and byte_size(existing_value) > 0 ->
                  updated_movement

                _other ->
                  Map.put(updated_movement, key, value)
              end
            end)

          _other ->
            movement
        end
      end)

    if movements != template.movements do
      template
      |> Ecto.Changeset.change(movements: movements)
      |> Repo.update!()
    end
  end
end

Repo.insert!(
  %User{
    id: local_id,
    email: "owner@ted.local",
    name: "Local coach",
    email_verified_at: now
  },
  on_conflict: :nothing
)

Repo.insert!(
  %Profile{
    user_id: local_id,
    primary_goal: "strength",
    experience_level: "intermediate",
    training_days_per_week: 3,
    session_minutes: 50,
    equipment: ["barbell", "rack", "bench"],
    daily_energy_target_kcal: 2_400,
    daily_protein_target_g: 160
  },
  on_conflict: :nothing
)

unless Repo.exists?(
         from(check_in in CheckIn,
           where:
             check_in.user_id == ^local_id and
               check_in.note == "Ready for a normal session."
         )
       ) do
  Repo.insert!(
    %CheckIn{
      user_id: local_id,
      date: today,
      weight_kg: Decimal.new("82.4"),
      sleep_hours: Decimal.new("7.5"),
      energy: 4,
      soreness: 2,
      nutrition_adherence: 4,
      note: "Ready for a normal session."
    },
    on_conflict: :nothing
  )
end

unless Repo.exists?(
         from(workout in Workout,
           where: workout.user_id == ^local_id and workout.name == "Full-body strength A"
         )
       ) do
  Repo.insert!(%Workout{
    user_id: local_id,
    performed_on: Date.add(today, -2),
    name: "Full-body strength A",
    duration_minutes: 48,
    perceived_exertion: 7,
    movements: [%{"name" => "Squat", "sets" => 3, "repetitions" => 5}]
  })
end

unless Repo.exists?(
         from(template in WorkoutTemplate,
           where: template.user_id == ^local_id and template.name == "Full-body strength A"
         )
       ) do
  Repo.insert!(%WorkoutTemplate{
    user_id: local_id,
    name: "Full-body strength A",
    description: "A repeatable full-body barbell session with clear setup and rest guidance.",
    estimated_duration_minutes: 50,
    image_url: "/assets/workouts/full-body-strength-a.png",
    image_alt:
      "Three-panel reference illustration showing a barbell squat, a barbell bench press, and a bent-over barbell row.",
    movements: [
      %{
        "id" => "back-squat",
        "name" => "Barbell squat",
        "image_url" => "/assets/exercises/barbell-squat.png",
        "image_alt" => "Original reference illustration of a barbell back squat.",
        "video_url" => "https://www.youtube.com/watch?v=8PMjqgR8Wa8",
        "sets" => 3,
        "repetitions" => "5",
        "rest_seconds" => 150,
        "instructions" =>
          "Use a load you can control with clean technique and stop if pain increases or movement quality deteriorates."
      },
      %{
        "id" => "bench-press",
        "name" => "Barbell bench press",
        "image_url" => "/assets/exercises/barbell-bench-press.png",
        "image_alt" => "Original reference illustration of a barbell bench press.",
        "video_url" => "https://www.youtube.com/watch?v=_bwO1u-hglA",
        "sets" => 3,
        "repetitions" => "5",
        "rest_seconds" => 150,
        "instructions" =>
          "Keep the movement controlled and use a load you can manage safely in the available setup."
      },
      %{
        "id" => "barbell-row",
        "name" => "Bent-over barbell row",
        "image_url" => "/assets/exercises/barbell-row.png",
        "image_alt" => "Original reference illustration of a bent-over barbell row.",
        "video_url" => "https://www.youtube.com/watch?v=kBWAon7ItDw",
        "sets" => 3,
        "repetitions" => "8",
        "rest_seconds" => 120,
        "instructions" =>
          "Keep the repetitions controlled and stop if the movement becomes painful or unstable."
      }
    ]
  })
end

unless Repo.exists?(
         from(template in WorkoutTemplate,
           where: template.user_id == ^local_id and template.name == "Full-body strength B"
         )
       ) do
  Repo.insert!(%WorkoutTemplate{
    user_id: local_id,
    name: "Full-body strength B",
    description:
      "A second full-body barbell session that can alternate with Full-body strength A.",
    estimated_duration_minutes: 50,
    image_url: "/assets/workouts/full-body-strength-b.png",
    image_alt:
      "Three-panel reference illustration showing a barbell deadlift, a standing barbell overhead press, and a rear-foot-elevated split squat with dumbbells.",
    movements: [
      %{
        "id" => "deadlift",
        "name" => "Barbell deadlift",
        "image_url" => "/assets/exercises/barbell-deadlift.png",
        "image_alt" => "Original reference illustration of a barbell deadlift.",
        "video_url" => "https://www.youtube.com/watch?v=oN8VgSgnhNk",
        "sets" => 3,
        "repetitions" => "5",
        "rest_seconds" => 180,
        "instructions" =>
          "Use a load and setup you can control. Stop the session if pain increases or the movement becomes unstable."
      },
      %{
        "id" => "overhead-press",
        "name" => "Standing barbell overhead press",
        "image_url" => "/assets/exercises/standing-barbell-overhead-press.png",
        "image_alt" => "Original reference illustration of a standing barbell overhead press.",
        "video_url" => "https://www.youtube.com/watch?v=yEbczj_FGyI",
        "sets" => 3,
        "repetitions" => "5",
        "rest_seconds" => 150,
        "instructions" =>
          "Use a load you can control and keep the repetitions smooth rather than forcing progression."
      },
      %{
        "id" => "split-squat",
        "name" => "Rear-foot-elevated split squat",
        "image_url" => "/assets/exercises/rear-foot-elevated-split-squat.png",
        "image_alt" => "Original reference illustration of a rear-foot-elevated split squat.",
        "video_url" => "https://www.youtube.com/watch?v=dWHkwgY9I08",
        "sets" => 3,
        "repetitions" => "8 each side",
        "rest_seconds" => 120,
        "instructions" =>
          "Use a comfortable range of motion and stop if pain increases or balance is unreliable."
      }
    ]
  })
end

unless Repo.exists?(
         from(template in WorkoutTemplate,
           where: template.user_id == ^local_id and template.name == "Machine full-body A"
         )
       ) do
  Repo.insert!(%WorkoutTemplate{
    user_id: local_id,
    name: "Machine full-body A",
    description:
      "A repeatable full-body session using selectorized and cable equipment, with a visual reference and demonstration for every movement.",
    estimated_duration_minutes: 55,
    image_url: "/assets/exercises/machine-chest-press.png",
    image_alt: "Original reference illustration of a selectorized machine chest press.",
    movements: [
      %{
        "id" => "machine-leg-press",
        "name" => "Machine leg press",
        "image_url" => "/assets/exercises/machine-leg-press.png",
        "image_alt" => "Original reference illustration of a horizontal selectorized leg press.",
        "video_url" => "https://www.youtube.com/watch?v=nDh_BlnLCGc",
        "sets" => 3,
        "repetitions" => "8 to 12",
        "rest_seconds" => 120,
        "instructions" =>
          "Place both feet evenly on the platform, keep your lower back supported, and use only a range you can control without pain."
      },
      %{
        "id" => "machine-chest-press",
        "name" => "Machine chest press",
        "image_url" => "/assets/exercises/machine-chest-press.png",
        "image_alt" => "Original reference illustration of a selectorized machine chest press.",
        "video_url" => "https://www.youtube.com/watch?v=Qu7-ceCvq7w",
        "sets" => 3,
        "repetitions" => "8 to 12",
        "rest_seconds" => 90,
        "instructions" =>
          "Set the handles at mid-chest height, keep your shoulder blades supported, and press without locking the elbows forcefully."
      },
      %{
        "id" => "lat-pulldown",
        "name" => "Lat pulldown",
        "image_url" => "/assets/exercises/lat-pulldown.png",
        "image_alt" => "Original reference illustration of a wide-grip lat pulldown.",
        "video_url" => "https://www.youtube.com/watch?v=bNmvKpJSWKM",
        "sets" => 3,
        "repetitions" => "8 to 12",
        "rest_seconds" => 90,
        "instructions" =>
          "Secure your thighs under the pads, keep your torso tall, and pull the bar toward the upper chest without leaning back sharply."
      },
      %{
        "id" => "seated-cable-row",
        "name" => "Seated cable row",
        "image_url" => "/assets/exercises/seated-cable-row.png",
        "image_alt" =>
          "Original reference illustration of a seated cable row with a close-grip handle.",
        "video_url" => "https://www.youtube.com/watch?v=8QuMq1GMMng",
        "sets" => 3,
        "repetitions" => "8 to 12",
        "rest_seconds" => 90,
        "instructions" =>
          "Keep your torso upright, pull the handle toward the lower ribs, and return it under control without rounding your back."
      },
      %{
        "id" => "machine-shoulder-press",
        "name" => "Machine shoulder press",
        "image_url" => "/assets/exercises/machine-shoulder-press.png",
        "image_alt" =>
          "Original reference illustration of a selectorized machine shoulder press.",
        "video_url" => "https://www.youtube.com/watch?v=6v4nrRVySj0",
        "sets" => 3,
        "repetitions" => "8 to 12",
        "rest_seconds" => 90,
        "instructions" =>
          "Adjust the seat so the handles start near ear height, keep your back on the pad, and press in a controlled range."
      },
      %{
        "id" => "machine-leg-extension",
        "name" => "Machine leg extension",
        "image_url" => "/assets/exercises/machine-leg-extension.png",
        "image_alt" => "Original reference illustration of a selectorized leg extension.",
        "video_url" => "https://www.youtube.com/watch?v=ztNBgrGy6FQ",
        "sets" => 2,
        "repetitions" => "10 to 15",
        "rest_seconds" => 75,
        "instructions" =>
          "Align your knees with the machine pivot, lift smoothly, and lower under control without forcing the knee joint at the top."
      }
    ]
  })
end

unless Repo.exists?(
         from(template in WorkoutTemplate,
           where: template.user_id == ^local_id and template.name == "Machine and cable B"
         )
       ) do
  Repo.insert!(%WorkoutTemplate{
    user_id: local_id,
    name: "Machine and cable B",
    description:
      "A complementary machine and cable session that includes posterior-leg, hip, arm, and vertical-pulling movements.",
    estimated_duration_minutes: 50,
    image_url: "/assets/exercises/machine-prone-leg-curl.png",
    image_alt: "Original reference illustration of a prone selectorized leg curl.",
    movements: [
      %{
        "id" => "machine-prone-leg-curl",
        "name" => "Machine prone leg curl",
        "image_url" => "/assets/exercises/machine-prone-leg-curl.png",
        "image_alt" => "Original reference illustration of a prone selectorized leg curl.",
        "video_url" => "https://www.youtube.com/watch?v=lGNeJsdqJwg",
        "sets" => 3,
        "repetitions" => "10 to 15",
        "rest_seconds" => 75,
        "instructions" =>
          "Keep your hips in contact with the pad, curl the roller by bending the knees, and lower without snapping the weight stack."
      },
      %{
        "id" => "machine-hip-abduction",
        "name" => "Machine hip abduction",
        "image_url" => "/assets/exercises/machine-hip-abduction.png",
        "image_alt" => "Original reference illustration of a selectorized hip abduction machine.",
        "video_url" => "https://www.youtube.com/watch?v=OjI5OpV6IWA",
        "sets" => 2,
        "repetitions" => "12 to 15",
        "rest_seconds" => 60,
        "instructions" =>
          "Set the pads comfortably above the knees, keep your pelvis supported, and move the thighs outward with control."
      },
      %{
        "id" => "machine-hip-adduction",
        "name" => "Machine hip adduction",
        "image_url" => "/assets/exercises/machine-hip-adduction.png",
        "image_alt" => "Original reference illustration of a selectorized hip adduction machine.",
        "video_url" => "https://www.youtube.com/watch?v=fwpMYCWdUNY",
        "sets" => 2,
        "repetitions" => "12 to 15",
        "rest_seconds" => 60,
        "instructions" =>
          "Set the pads comfortably above the knees, keep your pelvis supported, and bring the thighs inward without using momentum."
      },
      %{
        "id" => "cable-triceps-pressdown",
        "name" => "Cable triceps pressdown",
        "image_url" => "/assets/exercises/cable-triceps-pressdown.png",
        "image_alt" =>
          "Original reference illustration of a cable triceps pressdown with a straight bar.",
        "video_url" => "https://www.youtube.com/watch?v=1FjkhpZsaxc",
        "sets" => 2,
        "repetitions" => "10 to 15",
        "rest_seconds" => 60,
        "instructions" =>
          "Keep the elbows close to your ribs, press the bar down by straightening the elbows, and avoid swinging the torso."
      },
      %{
        "id" => "cable-biceps-curl",
        "name" => "Cable biceps curl",
        "image_url" => "/assets/exercises/cable-biceps-curl.png",
        "image_alt" =>
          "Original reference illustration of a standing cable biceps curl with a straight bar.",
        "video_url" => "https://www.youtube.com/watch?v=CrbTqNOlFgE",
        "sets" => 2,
        "repetitions" => "10 to 15",
        "rest_seconds" => 60,
        "instructions" =>
          "Keep the elbows close to your sides, curl the bar without leaning back, and lower it slowly until the arms are nearly straight."
      },
      %{
        "id" => "pull-up",
        "name" => "Pull-up",
        "image_url" => "/assets/exercises/pull-up.png",
        "image_alt" => "Original reference illustration of a strict bodyweight pull-up.",
        "video_url" => "https://www.youtube.com/watch?v=9rckBLbVe8c",
        "sets" => 3,
        "repetitions" => "3 to 8",
        "rest_seconds" => 120,
        "instructions" =>
          "Start from a controlled hang, pull without kicking, and stop each set before the movement becomes painful or unstable."
      }
    ]
  })
end

unless Repo.exists?(
         from(meal in Meal,
           where:
             meal.user_id == ^local_id and
               meal.description == "Yogurt, oats, berries, and nuts"
         )
       ) do
  Repo.insert!(%Meal{
    user_id: local_id,
    occurred_at: now,
    description: "Yogurt, oats, berries, and nuts",
    energy_kcal: 620,
    protein_g: Decimal.new("42")
  })
end

unless Repo.exists?(
         from(objective in Objective,
           where:
             objective.user_id == ^local_id and
               objective.label == "Deadlift 150 kilograms with clean technique"
         )
       ) do
  {:ok, _objective} =
    Coaching.set_objective(local_id, %{
      "kind" => "strength",
      "label" => "Deadlift 150 kilograms with clean technique",
      "metric" => "deadlift_one_repetition_max_kg",
      "baseline_value" => 125,
      "target_value" => 150,
      "unit" => "kg",
      "target_date" => Date.add(today, 120),
      "priority" => 5
    })
end

unless Repo.exists?(from(plan in Plan, where: plan.user_id == ^local_id)) do
  {:ok, _plan} = Coaching.build_plan(local_id, today)
end

Repo.insert!(
  %User{id: alex_id, email: "alex@ted.local", name: "Alex", email_verified_at: now},
  on_conflict: :nothing
)

Repo.insert!(
  %Profile{
    user_id: alex_id,
    primary_goal: "general_fitness",
    experience_level: "beginner",
    training_days_per_week: 2,
    session_minutes: 35,
    equipment: []
  },
  on_conflict: :nothing
)

unless Repo.exists?(
         from(template in WorkoutTemplate,
           where: template.user_id == ^alex_id and template.name == "Foundational full-body"
         )
       ) do
  Repo.insert!(%WorkoutTemplate{
    user_id: alex_id,
    name: "Foundational full-body",
    description: "A concise full-body session using simple dumbbell and bodyweight movements.",
    estimated_duration_minutes: 30,
    image_url: "/assets/workouts/foundational-full-body-a.png",
    image_alt:
      "Three-panel reference illustration showing a goblet squat, a push-up, and a single-arm dumbbell row supported by a bench.",
    movements: [
      %{
        "id" => "goblet-squat",
        "name" => "Goblet squat",
        "image_url" => "/assets/exercises/goblet-squat.png",
        "image_alt" => "Original reference illustration of a goblet squat with a dumbbell.",
        "video_url" => "https://www.youtube.com/watch?v=AxfrYsoektQ",
        "sets" => 3,
        "repetitions" => "8",
        "rest_seconds" => 90,
        "instructions" =>
          "Use a comfortable range of motion and a load you can control. Stop if pain increases or balance becomes unreliable."
      },
      %{
        "id" => "push-up",
        "name" => "Push-up",
        "image_url" => "/assets/exercises/push-up.png",
        "image_alt" => "Original reference illustration of a bodyweight push-up.",
        "video_url" => "https://www.youtube.com/watch?v=IODxDxX7oi4",
        "sets" => 3,
        "repetitions" => "6 to 10",
        "rest_seconds" => 90,
        "instructions" =>
          "Choose a variation that lets you move in a controlled way without pain or loss of position."
      },
      %{
        "id" => "single-arm-row",
        "name" => "Single-arm dumbbell row",
        "image_url" => "/assets/exercises/single-arm-dumbbell-row.png",
        "image_alt" =>
          "Original reference illustration of a single-arm dumbbell row supported by a bench.",
        "video_url" => "https://www.youtube.com/watch?v=nNpxG9fGHoM",
        "sets" => 3,
        "repetitions" => "8 each side",
        "rest_seconds" => 90,
        "instructions" =>
          "Use a stable support and keep the repetitions controlled. Stop if the movement becomes painful or unstable."
      }
    ]
  })
end

unless Repo.exists?(
         from(template in WorkoutTemplate,
           where: template.user_id == ^alex_id and template.name == "Foundational full-body B"
         )
       ) do
  Repo.insert!(%WorkoutTemplate{
    user_id: alex_id,
    name: "Foundational full-body B",
    description:
      "A minimal-equipment full-body session that can alternate with Foundational full-body.",
    estimated_duration_minutes: 30,
    image_url: "/assets/exercises/dumbbell-hip-hinge.png",
    image_alt: "Original reference illustration of a dumbbell hip hinge.",
    movements: [
      %{
        "id" => "dumbbell-hip-hinge",
        "name" => "Dumbbell hip hinge",
        "image_url" => "/assets/exercises/dumbbell-hip-hinge.png",
        "image_alt" => "Original reference illustration of a dumbbell hip hinge.",
        "video_url" => "https://www.youtube.com/watch?v=tnQ8NQG9XEw",
        "sets" => 3,
        "repetitions" => "10",
        "rest_seconds" => 90,
        "instructions" =>
          "Use a range you can control and stop if pain increases or your position becomes unreliable."
      },
      %{
        "id" => "pike-push-up",
        "name" => "Pike push-up",
        "image_url" => "/assets/exercises/pike-push-up.png",
        "image_alt" => "Original reference illustration of a pike push-up.",
        "video_url" => "https://www.youtube.com/watch?v=66x0qQiJ-MA",
        "sets" => 3,
        "repetitions" => "6 to 10",
        "rest_seconds" => 90,
        "instructions" =>
          "Choose a variation that lets you move in a controlled way without pain or loss of position."
      },
      %{
        "id" => "split-squat",
        "name" => "Split squat",
        "image_url" => "/assets/exercises/split-squat.png",
        "image_alt" => "Original reference illustration of a bodyweight split squat.",
        "video_url" => "https://www.youtube.com/watch?v=zCsZwLeXrCg",
        "sets" => 3,
        "repetitions" => "8 each side",
        "rest_seconds" => 90,
        "instructions" =>
          "Use a comfortable range of motion and stop if pain increases or balance becomes unreliable."
      }
    ]
  })
end

unless Repo.exists?(
         from(objective in Objective,
           where:
             objective.user_id == ^alex_id and
               objective.label == "Complete two strength sessions each week"
         )
       ) do
  {:ok, _objective} =
    Coaching.set_objective(alex_id, %{
      "kind" => "consistency",
      "label" => "Complete two strength sessions each week",
      "metric" => "weekly_strength_sessions",
      "baseline_value" => 0,
      "target_value" => 2,
      "unit" => "sessions",
      "target_date" => Date.add(today, 90),
      "priority" => 5
    })
end

unless Repo.exists?(from(plan in Plan, where: plan.user_id == ^alex_id)) do
  {:ok, _plan} = Coaching.build_plan(alex_id, today)
end

ensure_template_guidance.(local_id, "Full-body strength A", %{
  "back-squat" => %{
    "image_url" => "/assets/exercises/barbell-squat.png",
    "image_alt" => "Original reference illustration of a barbell back squat.",
    "video_url" => "https://www.youtube.com/watch?v=8PMjqgR8Wa8"
  },
  "bench-press" => %{
    "image_url" => "/assets/exercises/barbell-bench-press.png",
    "image_alt" => "Original reference illustration of a barbell bench press.",
    "video_url" => "https://www.youtube.com/watch?v=_bwO1u-hglA"
  },
  "barbell-row" => %{
    "image_url" => "/assets/exercises/barbell-row.png",
    "image_alt" => "Original reference illustration of a bent-over barbell row.",
    "video_url" => "https://www.youtube.com/watch?v=kBWAon7ItDw"
  }
})

ensure_template_guidance.(local_id, "Full-body strength B", %{
  "deadlift" => %{
    "image_url" => "/assets/exercises/barbell-deadlift.png",
    "image_alt" => "Original reference illustration of a barbell deadlift.",
    "video_url" => "https://www.youtube.com/watch?v=oN8VgSgnhNk"
  },
  "overhead-press" => %{
    "image_url" => "/assets/exercises/standing-barbell-overhead-press.png",
    "image_alt" => "Original reference illustration of a standing barbell overhead press.",
    "video_url" => "https://www.youtube.com/watch?v=yEbczj_FGyI"
  },
  "split-squat" => %{
    "image_url" => "/assets/exercises/rear-foot-elevated-split-squat.png",
    "image_alt" => "Original reference illustration of a rear-foot-elevated split squat.",
    "video_url" => "https://www.youtube.com/watch?v=dWHkwgY9I08"
  }
})

ensure_template_guidance.(alex_id, "Foundational full-body", %{
  "goblet-squat" => %{
    "image_url" => "/assets/exercises/goblet-squat.png",
    "image_alt" => "Original reference illustration of a goblet squat with a dumbbell.",
    "video_url" => "https://www.youtube.com/watch?v=AxfrYsoektQ"
  },
  "push-up" => %{
    "image_url" => "/assets/exercises/push-up.png",
    "image_alt" => "Original reference illustration of a bodyweight push-up.",
    "video_url" => "https://www.youtube.com/watch?v=IODxDxX7oi4"
  },
  "single-arm-row" => %{
    "image_url" => "/assets/exercises/single-arm-dumbbell-row.png",
    "image_alt" =>
      "Original reference illustration of a single-arm dumbbell row supported by a bench.",
    "video_url" => "https://www.youtube.com/watch?v=nNpxG9fGHoM"
  }
})

ensure_template_guidance.(alex_id, "Foundational full-body B", %{
  "dumbbell-hip-hinge" => %{
    "image_url" => "/assets/exercises/dumbbell-hip-hinge.png",
    "image_alt" => "Original reference illustration of a dumbbell hip hinge.",
    "video_url" => "https://www.youtube.com/watch?v=tnQ8NQG9XEw"
  },
  "pike-push-up" => %{
    "image_url" => "/assets/exercises/pike-push-up.png",
    "image_alt" => "Original reference illustration of a pike push-up.",
    "video_url" => "https://www.youtube.com/watch?v=66x0qQiJ-MA"
  },
  "split-squat" => %{
    "image_url" => "/assets/exercises/split-squat.png",
    "image_alt" => "Original reference illustration of a bodyweight split squat.",
    "video_url" => "https://www.youtube.com/watch?v=zCsZwLeXrCg"
  }
})
