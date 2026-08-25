defmodule Ted.Accounts do
  @moduledoc "Manages the people who own coaching data."

  import Ecto.Query

  alias Ted.Accounts.{EmailVerificationToken, User}
  alias Ted.Repo

  @default_user_id "00000000-0000-0000-0000-000000000001"

  @spec default_user_id() :: Ecto.UUID.t()
  def default_user_id, do: @default_user_id

  @spec get_user(Ecto.UUID.t(), module()) :: {:ok, map()} | {:error, :not_found}
  def get_user(id, repo \\ Repo) do
    case repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user_map(user)}
    end
  end

  @spec get_user_by_email(String.t(), module()) :: {:ok, map()} | {:error, :not_found}
  def get_user_by_email(email, repo \\ Repo) when is_binary(email) do
    case repo.get_by(User, email: normalize_email(email)) do
      nil -> {:error, :not_found}
      user -> {:ok, user_map(user)}
    end
  end

  @spec create_user(map(), module()) :: {:ok, map()} | {:error, term()}
  def create_user(attrs, repo \\ Repo) when is_map(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> repo.insert()
    |> map_record(&user_map/1)
  end

  @spec create_verified_agent_user(map(), module()) :: {:ok, map()} | {:error, term()}
  def create_verified_agent_user(attrs, repo \\ Repo) when is_map(attrs) do
    %User{}
    |> User.verified_agent_changeset(attrs)
    |> repo.insert()
    |> map_record(&user_map/1)
  end

  @spec claim_user(String.t(), String.t(), String.t(), module()) ::
          {:ok, map()} | {:error, term()}
  def claim_user(email, name, password, repo \\ Repo)

  def claim_user(email, name, password, repo)
      when is_binary(email) and is_binary(name) and is_binary(password) do
    email = normalize_email(email)

    repo.transaction(fn ->
      email
      |> locked_user(repo)
      |> claim_locked_user(email, name, password, repo)
      |> unwrap_claim(repo)
    end)
    |> normalize_transaction()
  end

  def claim_user(_email, _name, _password, _repo), do: {:error, :invalid_request}

  @spec authenticate_user(String.t(), String.t(), module()) ::
          {:ok, map()} | {:error, :invalid_credentials}
  def authenticate_user(email, password, repo \\ Repo)

  def authenticate_user(email, password, repo)
      when is_binary(email) and is_binary(password) do
    user = repo.get_by(User, email: normalize_email(email))

    if User.valid_password?(user, password),
      do: {:ok, user_map(user)},
      else: {:error, :invalid_credentials}
  end

  def authenticate_user(_email, _password, _repo) do
    User.valid_password?(nil, nil)
    {:error, :invalid_credentials}
  end

  @spec deliver_email_verification(map(), (String.t() -> String.t()), module(), module()) ::
          {:ok, term()} | {:error, term()}
  def deliver_email_verification(%{id: user_id}, build_url, notifier, repo \\ Repo)
      when is_binary(user_id) and is_function(build_url, 1) and is_atom(notifier) do
    with %User{} = user <- repo.get(User, user_id),
         true <- is_binary(user.email),
         {encoded_token, token_record} <- EmailVerificationToken.build(user),
         {_, nil} <-
           repo.delete_all(
             from(token in EmailVerificationToken, where: token.user_id == ^user_id)
           ),
         {:ok, _token} <- repo.insert(token_record),
         {:ok, email} <- notifier.deliver_verification(user, build_url.(encoded_token)) do
      {:ok, email}
    else
      nil -> {:error, :not_found}
      false -> {:error, :email_required}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_user_by_email_verification_token(String.t(), module()) ::
          {:ok, map()} | {:error, :invalid_token}
  def get_user_by_email_verification_token(token, repo \\ Repo) do
    with {:ok, query} <- EmailVerificationToken.verification_query(token),
         {%User{} = user, %EmailVerificationToken{}} <- repo.one(query) do
      {:ok, user_map(user)}
    else
      _invalid -> {:error, :invalid_token}
    end
  end

  @spec verify_user_email(String.t(), module()) :: {:ok, map()} | {:error, term()}
  def verify_user_email(token, repo \\ Repo) do
    repo.transaction(fn -> verify_user_email_transaction(token, repo) end)
    |> normalize_transaction()
  end

  defp map_record({:ok, record}, mapper), do: {:ok, mapper.(record)}
  defp map_record({:error, reason}, _mapper), do: {:error, reason}

  defp locked_user(email, repo) do
    repo.one(from(user in User, where: user.email == ^email, lock: "FOR UPDATE"))
  end

  defp claim_locked_user(nil, email, name, password, repo) do
    %User{}
    |> User.agent_signup_changeset(%{"email" => email, "name" => name, "password" => password})
    |> repo.insert()
  end

  defp claim_locked_user(%User{}, _email, _name, _password, _repo) do
    Argon2.no_user_verify()
    {:error, :account_exists}
  end

  defp unwrap_claim({:ok, claimed_user}, _repo), do: user_map(claimed_user)
  defp unwrap_claim({:error, reason}, repo), do: repo.rollback(reason)

  defp verify_user_email_transaction(token, repo) do
    with {:ok, query} <- EmailVerificationToken.verification_query(token),
         {%User{} = user, %EmailVerificationToken{}} <-
           repo.one(from(record in query, lock: "FOR UPDATE")),
         {:ok, user} <-
           user
           |> Ecto.Changeset.change(
             email_verified_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
           )
           |> repo.update() do
      repo.delete_all(from(record in EmailVerificationToken, where: record.user_id == ^user.id))
      user_map(user)
    else
      _invalid -> repo.rollback(:invalid_token)
    end
  end

  defp normalize_transaction({:ok, user}), do: {:ok, user}
  defp normalize_transaction({:error, reason}), do: {:error, reason}
  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp user_map(user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      email_verified_at: user.email_verified_at,
      created_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
