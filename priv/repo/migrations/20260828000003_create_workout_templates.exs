defmodule Ted.Repo.Migrations.CreateWorkoutTemplates do
  use Ecto.Migration

  def change do
    create table(:workout_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :description, :text
      add :estimated_duration_minutes, :integer
      add :movements, {:array, :map}, null: false, default: []
      add :image_url, :text, null: false
      add :image_alt, :text, null: false
      add :version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workout_templates, [:user_id, :updated_at])

    alter table(:workouts) do
      add :workout_template_id,
          references(:workout_templates, type: :binary_id, on_delete: :nilify_all)

      add :workout_template_version, :integer
    end

    create index(:workouts, [:workout_template_id])
  end
end
