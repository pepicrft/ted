defmodule Ted.Repo.Migrations.AddOAuthGrantFamilies do
  use Ecto.Migration

  def change do
    alter table(:oauth_authorization_codes) do
      add(:grant_id, :binary_id, null: false)
    end

    alter table(:oauth_access_tokens) do
      add(:grant_id, :binary_id, null: false)
    end

    alter table(:oauth_refresh_tokens) do
      add(:grant_id, :binary_id, null: false)
    end

    create(index(:oauth_authorization_codes, [:grant_id]))
    create(index(:oauth_access_tokens, [:grant_id]))
    create(index(:oauth_refresh_tokens, [:grant_id]))
  end
end
