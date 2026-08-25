defmodule Ted.Coaching.CheckIn do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "check_ins" do
    field(:date, :date)
    field(:weight_kg, :decimal)
    field(:sleep_hours, :decimal)
    field(:energy, :integer)
    field(:soreness, :integer)
    field(:pain, :integer)
    field(:nutrition_adherence, :integer)
    field(:note, :string)

    belongs_to(:user, Ted.Accounts.User)

    timestamps()
  end

  def changeset(check_in, attrs) do
    check_in
    |> cast(attrs, [
      :user_id,
      :date,
      :weight_kg,
      :sleep_hours,
      :energy,
      :soreness,
      :pain,
      :nutrition_adherence,
      :note
    ])
    |> validate_required([:user_id, :date])
    |> validate_number(:weight_kg, greater_than: 20, less_than: 500)
    |> validate_number(:sleep_hours, greater_than_or_equal_to: 0, less_than_or_equal_to: 24)
    |> validate_score(:energy)
    |> validate_score(:soreness)
    |> validate_number(:pain, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_score(:nutrition_adherence)
    |> validate_length(:note, max: 2_000)
    |> unique_constraint([:user_id, :date])
  end

  defp validate_score(changeset, field),
    do: validate_number(changeset, field, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
end
