defmodule Ted.Repo.Migrations.RemoveTelegramConnections do
  use Ecto.Migration

  def up do
    drop table(:telegram_connections)
  end

  def down do
    create table(:telegram_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :telegram_user_id, :text, null: false
      add :chat_id, :text, null: false
      add :username, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:telegram_connections, [:telegram_user_id])
    create index(:telegram_connections, [:user_id])
  end
end
