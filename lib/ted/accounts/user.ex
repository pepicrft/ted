defmodule Ted.Accounts.User do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          name: String.t(),
          hashed_password: String.t() | nil,
          signed_up_by_agent: boolean(),
          email_verified_at: DateTime.t() | nil
        }

  schema "users" do
    field(:email, :string)
    field(:name, :string)
    field(:hashed_password, :string, redact: true)
    field(:password, :string, virtual: true, redact: true)
    field(:signed_up_by_agent, :boolean, default: false)
    field(:email_verified_at, :utc_datetime_usec)

    has_one(:profile, Ted.Coaching.Profile)
    has_many(:check_ins, Ted.Coaching.CheckIn)
    has_many(:workouts, Ted.Coaching.Workout)
    has_many(:meals, Ted.Coaching.Meal)
    has_many(:objectives, Ted.Coaching.Objective)
    has_many(:plans, Ted.Coaching.Plan)
    has_many(:telegram_connections, Ted.Telegram.Connection)

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> normalize_email()
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_email()
    |> unique_constraint(:email)
  end

  def agent_signup_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password])
    |> normalize_email()
    |> validate_required([:email, :name, :password])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:password, min: 12, max: 72)
    |> validate_email()
    |> unique_constraint(:email)
    |> put_change(:signed_up_by_agent, true)
    |> hash_password()
  end

  def verified_agent_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> normalize_email()
    |> validate_required([:email, :name])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_email()
    |> unique_constraint(:email)
    |> put_change(:signed_up_by_agent, true)
    |> put_change(:email_verified_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and is_binary(password) and byte_size(password) > 0 and
             byte_size(password) <= 72,
      do: Argon2.verify_pass(password, hash)

  def valid_password?(_user, _password) do
    Argon2.no_user_verify()
    false
  end

  defp normalize_email(changeset),
    do: update_change(changeset, :email, &(&1 |> String.trim() |> String.downcase()))

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length(:email, max: 254)
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      password when is_binary(password) and changeset.valid? ->
        changeset
        |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
        |> delete_change(:password)

      _password ->
        changeset
    end
  end
end
