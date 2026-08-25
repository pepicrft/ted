defmodule Ted.Coaching.Profile do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @goals ~w(strength muscle_gain fat_loss general_fitness)
  @experience_levels ~w(beginner intermediate advanced)

  schema "coaching_profiles" do
    field(:timezone, :string, default: "Etc/UTC")
    field(:primary_goal, :string, default: "strength")
    field(:experience_level, :string, default: "beginner")
    field(:training_days_per_week, :integer, default: 3)
    field(:session_minutes, :integer, default: 45)
    field(:equipment, {:array, :string}, default: [])
    field(:dietary_preferences, {:array, :string}, default: [])
    field(:daily_energy_target_kcal, :integer)
    field(:daily_protein_target_g, :integer)

    belongs_to(:user, Ted.Accounts.User)

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :user_id,
      :timezone,
      :primary_goal,
      :experience_level,
      :training_days_per_week,
      :session_minutes,
      :equipment,
      :dietary_preferences,
      :daily_energy_target_kcal,
      :daily_protein_target_g
    ])
    |> validate_required([
      :user_id,
      :timezone,
      :primary_goal,
      :experience_level,
      :training_days_per_week,
      :session_minutes
    ])
    |> validate_inclusion(:primary_goal, @goals)
    |> validate_inclusion(:experience_level, @experience_levels)
    |> validate_number(:training_days_per_week, greater_than: 0, less_than_or_equal_to: 7)
    |> validate_number(:session_minutes, greater_than_or_equal_to: 15, less_than_or_equal_to: 180)
    |> validate_number(:daily_energy_target_kcal,
      greater_than_or_equal_to: 800,
      less_than_or_equal_to: 8_000
    )
    |> validate_number(:daily_protein_target_g,
      greater_than_or_equal_to: 20,
      less_than_or_equal_to: 500
    )
    |> unique_constraint(:user_id)
  end
end
