defmodule Ted.Repo.Migrations.AddOAuthClientAuthorization do
  use Ecto.Migration

  def change do
    create table(:oauth_clients, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :text, null: false)
      add(:redirect_uris, {:array, :text}, null: false)
      add(:grant_types, {:array, :text}, null: false)
      add(:created_at, :bigint, null: false)
    end

    create table(:oauth_authorization_codes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:code_hash, :binary, null: false)

      add(:client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:redirect_uri, :text, null: false)
      add(:code_challenge, :text, null: false)
      add(:scopes, :text, null: false)
      add(:resource, :text, null: false)
      add(:expires_at, :bigint, null: false)
      add(:consumed_at, :bigint)
    end

    create(unique_index(:oauth_authorization_codes, [:code_hash]))
    create(index(:oauth_authorization_codes, [:client_id]))
    create(index(:oauth_authorization_codes, [:user_id]))

    create table(:oauth_access_tokens, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:token_hash, :binary, null: false)

      add(:client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:scopes, :text, null: false)
      add(:resource, :text, null: false)
      add(:created_at, :bigint, null: false)
      add(:expires_at, :bigint, null: false)
      add(:revoked_at, :bigint)
    end

    create(unique_index(:oauth_access_tokens, [:token_hash]))
    create(index(:oauth_access_tokens, [:client_id]))
    create(index(:oauth_access_tokens, [:user_id]))

    create table(:oauth_refresh_tokens, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:token_hash, :binary, null: false)

      add(:client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:scopes, :text, null: false)
      add(:resource, :text, null: false)
      add(:created_at, :bigint, null: false)
      add(:expires_at, :bigint, null: false)
      add(:revoked_at, :bigint)
    end

    create(unique_index(:oauth_refresh_tokens, [:token_hash]))
    create(index(:oauth_refresh_tokens, [:client_id]))
    create(index(:oauth_refresh_tokens, [:user_id]))
  end
end
