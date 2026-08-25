defmodule Ted.Coaching.Meal do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "meals" do
    field(:occurred_at, :utc_datetime_usec)
    field(:description, :string)
    field(:energy_kcal, :integer)
    field(:protein_g, :decimal)
    field(:carbohydrate_g, :decimal)
    field(:fat_g, :decimal)

    belongs_to(:user, Ted.Accounts.User)

    timestamps()
  end

  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [
      :user_id,
      :occurred_at,
      :description,
      :energy_kcal,
      :protein_g,
      :carbohydrate_g,
      :fat_g
    ])
    |> validate_required([:user_id, :occurred_at, :description])
    |> validate_length(:description, min: 1, max: 500)
    |> validate_number(:energy_kcal, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:protein_g, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:carbohydrate_g, greater_than_or_equal_to: 0, less_than_or_equal_to: 2_000)
    |> validate_number(:fat_g, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
  end
end
