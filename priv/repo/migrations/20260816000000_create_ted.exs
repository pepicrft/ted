defmodule Ted.Repo.Migrations.CreateTed do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :text
      add :name, :text, null: false
      add :hashed_password, :text
      add :signed_up_by_agent, :boolean, null: false, default: false
      add :email_verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create table(:coaching_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :timezone, :text, null: false, default: "Etc/UTC"
      add :primary_goal, :text, null: false, default: "strength"
      add :experience_level, :text, null: false, default: "beginner"
      add :training_days_per_week, :integer, null: false, default: 3
      add :session_minutes, :integer, null: false, default: 45
      add :equipment, {:array, :text}, null: false, default: []
      add :dietary_preferences, {:array, :text}, null: false, default: []
      add :daily_energy_target_kcal, :integer
      add :daily_protein_target_g, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:coaching_profiles, [:user_id])

    create table(:objectives, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :label, :text, null: false
      add :metric, :text
      add :baseline_value, :decimal, precision: 12, scale: 3
      add :target_value, :decimal, precision: 12, scale: 3
      add :unit, :text
      add :target_date, :date
      add :priority, :integer, null: false, default: 3
      add :status, :text, null: false, default: "active"
      add :details, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:objectives, [:user_id, :status, :priority])

    create table(:coaching_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :status, :text, null: false, default: "active"
      add :starts_on, :date, null: false
      add :review_on, :date, null: false
      add :objective_snapshot, {:array, :map}, null: false, default: []
      add :strategy, :map, null: false, default: %{}
      add :rationale, {:array, :text}, null: false, default: []
      add :evidence, {:array, :text}, null: false, default: []
      add :created_by, :text, null: false, default: "ted"
      add :superseded_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:coaching_plans, [:user_id, :version])
    create index(:coaching_plans, [:user_id, :status])

    create table(:check_ins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :weight_kg, :decimal, precision: 6, scale: 2
      add :sleep_hours, :decimal, precision: 4, scale: 2
      add :energy, :integer
      add :soreness, :integer
      add :pain, :integer
      add :nutrition_adherence, :integer
      add :note, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:check_ins, [:user_id, :date])

    create table(:workouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :performed_on, :date, null: false
      add :name, :text, null: false
      add :duration_minutes, :integer
      add :perceived_exertion, :integer
      add :movements, {:array, :map}, null: false, default: []
      add :notes, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workouts, [:user_id, :performed_on])

    create table(:meals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :description, :text, null: false
      add :energy_kcal, :integer
      add :protein_g, :decimal, precision: 7, scale: 2
      add :carbohydrate_g, :decimal, precision: 7, scale: 2
      add :fat_g, :decimal, precision: 7, scale: 2

      timestamps(type: :utc_datetime_usec)
    end

    create index(:meals, [:user_id, :occurred_at])

    create table(:plan_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :plan_id, references(:coaching_plans, type: :binary_id, on_delete: :delete_all),
        null: false

      add :next_plan_id, references(:coaching_plans, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_on, :date, null: false
      add :status, :text, null: false
      add :observations, :map, null: false, default: %{}
      add :decision, :map, null: false, default: %{}
      add :rationale, {:array, :text}, null: false, default: []
      add :confidence, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:plan_reviews, [:user_id, :reviewed_on])
    create index(:plan_reviews, [:plan_id])

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

    create table(:user_email_verification_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :sent_to, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_email_verification_tokens, [:token_hash])
    create index(:user_email_verification_tokens, [:user_id])

    create table(:agent_auth_registrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :registration_type, :text, null: false
      add :status, :text, null: false
      add :claim_email, :text
      add :claim_token_hash, :binary, null: false
      add :claim_attempt_token_hash, :binary
      add :user_code_hash, :binary
      add :created_at, :bigint, null: false
      add :expires_at, :bigint, null: false
      add :claim_attempt_expires_at, :bigint
      add :claimed_at, :bigint
      add :last_polled_at, :bigint
      add :claimed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :registration_address, :text
      add :claim_address, :text
      add :confirmed_address, :text
      add :failed_claim_attempts, :integer, null: false, default: 0
      add :failed_sign_in_attempts, :integer, null: false, default: 0
      add :email_verified, :boolean, null: false, default: false
      add :provider_issuer, :text
      add :provider_subject, :text
      add :provider_client_id, :text
      add :provider_jti, :text
    end

    create unique_index(:agent_auth_registrations, [:claim_token_hash])
    create unique_index(:agent_auth_registrations, [:claim_attempt_token_hash])
    create index(:agent_auth_registrations, [:claimed_by_user_id])
    create index(:agent_auth_registrations, [:registration_address, :created_at])
    create index(:agent_auth_registrations, [:provider_issuer, :provider_subject])
    create unique_index(:agent_auth_registrations, [:provider_issuer, :provider_jti])

    create table(:agent_auth_access_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token_hash, :binary, null: false
      add :registration_id,
          references(:agent_auth_registrations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :scopes, :text, null: false
      add :created_at, :bigint, null: false
      add :expires_at, :bigint, null: false
      add :revoked_at, :bigint
      add :resource, :text
    end

    create unique_index(:agent_auth_access_tokens, [:token_hash])
    create index(:agent_auth_access_tokens, [:registration_id])

    create table(:agent_auth_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :registration_id,
          references(:agent_auth_registrations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :created_at, :bigint, null: false
    end

    create index(:agent_auth_events, [:registration_id, :created_at])
  end
end
