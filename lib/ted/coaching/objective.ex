defmodule Ted.Coaching.Objective do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @kinds ~w(fat_loss muscle_gain body_recomposition strength consistency)
  @statuses ~w(active achieved paused)

  schema "objectives" do
    field(:kind, :string)
    field(:label, :string)
    field(:metric, :string)
    field(:baseline_value, :decimal)
    field(:target_value, :decimal)
    field(:unit, :string)
    field(:target_date, :date)
    field(:priority, :integer, default: 3)
    field(:status, :string, default: "active")
    field(:details, :map, default: %{})

    belongs_to(:user, Ted.Accounts.User)

    timestamps()
  end

  def changeset(objective, attrs) do
    objective
    |> cast(attrs, [
      :user_id,
      :kind,
      :label,
      :metric,
      :baseline_value,
      :target_value,
      :unit,
      :target_date,
      :priority,
      :status,
      :details
    ])
    |> validate_required([:user_id, :kind, :label])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:priority, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_length(:label, min: 1, max: 240)
    |> validate_length(:metric, max: 120)
    |> validate_length(:unit, max: 40)
  end
end
