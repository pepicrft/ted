defmodule Ted.Coaching.Workout do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "workouts" do
    field(:performed_on, :date)
    field(:name, :string)
    field(:duration_minutes, :integer)
    field(:perceived_exertion, :integer)
    field(:movements, {:array, :map}, default: [])
    field(:notes, :string)

    belongs_to(:user, Ted.Accounts.User)
    belongs_to(:workout_template, Ted.Coaching.WorkoutTemplate)

    field(:workout_template_version, :integer)

    timestamps()
  end

  def changeset(workout, attrs) do
    workout
    |> cast(attrs, [
      :user_id,
      :performed_on,
      :name,
      :duration_minutes,
      :perceived_exertion,
      :movements,
      :notes,
      :workout_template_id,
      :workout_template_version
    ])
    |> validate_required([:user_id, :performed_on, :name])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 480)
    |> validate_number(:perceived_exertion,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10
    )
    |> validate_length(:notes, max: 4_000)
    |> validate_number(:workout_template_version, greater_than: 0)
  end
end
