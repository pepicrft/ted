defmodule Ted.Coaching.Plan do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "coaching_plans" do
    field(:version, :integer)
    field(:status, :string, default: "active")
    field(:starts_on, :date)
    field(:review_on, :date)
    field(:objective_snapshot, {:array, :map}, default: [])
    field(:strategy, :map, default: %{})
    field(:rationale, {:array, :string}, default: [])
    field(:evidence, {:array, :string}, default: [])
    field(:created_by, :string, default: "ted")
    field(:superseded_at, :utc_datetime_usec)

    belongs_to(:user, Ted.Accounts.User)

    timestamps()
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :user_id,
      :version,
      :status,
      :starts_on,
      :review_on,
      :objective_snapshot,
      :strategy,
      :rationale,
      :evidence,
      :created_by,
      :superseded_at
    ])
    |> validate_required([
      :user_id,
      :version,
      :status,
      :starts_on,
      :review_on,
      :objective_snapshot,
      :strategy,
      :created_by
    ])
    |> validate_inclusion(:status, ~w(active superseded))
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:user_id, :version])
  end
end
