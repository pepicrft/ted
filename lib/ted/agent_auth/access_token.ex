defmodule Ted.AgentAuth.AccessToken do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_auth_access_tokens" do
    field(:token_hash, :binary)
    field(:registration_id, :binary_id)
    field(:scopes, :string)
    field(:created_at, :integer)
    field(:expires_at, :integer)
    field(:revoked_at, :integer)
    field(:resource, :string)
  end
end
