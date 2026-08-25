import Ecto.Query

alias Ted.Accounts.User
alias Ted.Coaching
alias Ted.Coaching.{CheckIn, Meal, Objective, Plan, Profile, Workout}
alias Ted.Repo

local_id = "00000000-0000-0000-0000-000000000001"
alex_id = "00000000-0000-0000-0000-000000000002"

now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
today = Date.utc_today()

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
