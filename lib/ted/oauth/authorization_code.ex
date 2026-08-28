defmodule Ted.OAuth.AuthorizationCode do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_authorization_codes" do
    field(:code_hash, :binary)
    field(:client_id, :binary_id)
    field(:user_id, :binary_id)
    field(:grant_id, :binary_id)
    field(:redirect_uri, :string)
    field(:code_challenge, :string)
    field(:scopes, :string)
    field(:resource, :string)
    field(:expires_at, :integer)
    field(:consumed_at, :integer)
  end
end
