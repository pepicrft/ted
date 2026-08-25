defmodule Ted.AgentAuth.Event do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_auth_events" do
    field(:registration_id, :binary_id)
    field(:name, :string)
    field(:metadata, :map, default: %{})
    field(:created_at, :integer)
  end
end
