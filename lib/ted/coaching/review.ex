defmodule Ted.Coaching.Review do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "plan_reviews" do
    field(:reviewed_on, :date)
    field(:status, :string)
    field(:observations, :map, default: %{})
    field(:decision, :map, default: %{})
    field(:rationale, {:array, :string}, default: [])
    field(:confidence, :string)

    belongs_to(:user, Ted.Accounts.User)
    belongs_to(:plan, Ted.Coaching.Plan)
    belongs_to(:next_plan, Ted.Coaching.Plan)

    timestamps()
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :user_id,
      :plan_id,
      :next_plan_id,
      :reviewed_on,
      :status,
      :observations,
      :decision,
      :rationale,
      :confidence
    ])
    |> validate_required([
      :user_id,
      :plan_id,
      :reviewed_on,
      :status,
      :observations,
      :decision,
      :confidence
    ])
    |> validate_inclusion(:status, ~w(adjusted no_change needs_data safety_hold))
    |> validate_inclusion(:confidence, ~w(low moderate high))
  end
end
