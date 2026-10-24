defmodule Ted.Repo.Migrations.AddWorkoutProgress do
  use Ecto.Migration

  def change do
    alter table(:workouts) do
      add(:status, :text, null: false, default: "completed")
      add(:completed_sets, {:array, :map}, null: false, default: [])
      add(:plan_id, references(:coaching_plans, type: :binary_id, on_delete: :nilify_all))
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)
    end

    create(
      unique_index(:workouts, [:user_id],
        name: :workouts_one_in_progress_per_user,
        where: "status = 'in_progress'"
      )
    )

    create(
      constraint(:workouts, :workouts_valid_status,
        check: "status IN ('in_progress', 'completed', 'cancelled')"
      )
    )
  end
end
