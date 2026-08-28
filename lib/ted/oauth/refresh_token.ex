defmodule Ted.OAuth.RefreshToken do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_refresh_tokens" do
    field(:token_hash, :binary)
    field(:client_id, :binary_id)
    field(:user_id, :binary_id)
    field(:grant_id, :binary_id)
    field(:scopes, :string)
    field(:resource, :string)
    field(:created_at, :integer)
    field(:expires_at, :integer)
    field(:revoked_at, :integer)
  end
end
