defmodule Ted.Telegram.Connection do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "telegram_connections" do
    field(:telegram_user_id, :string)
    field(:chat_id, :string)
    field(:username, :string)

    belongs_to(:user, Ted.Accounts.User)

    timestamps()
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:user_id, :telegram_user_id, :chat_id, :username])
    |> validate_required([:user_id, :telegram_user_id, :chat_id])
    |> unique_constraint(:telegram_user_id)
  end
end
