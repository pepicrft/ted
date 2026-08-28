defmodule Ted.OAuth.Client do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_clients" do
    field(:name, :string)
    field(:redirect_uris, {:array, :string})
    field(:grant_types, {:array, :string})
    field(:created_at, :integer)
  end
end
