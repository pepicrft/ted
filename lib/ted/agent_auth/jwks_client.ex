defmodule Ted.AgentAuth.JwksClient do
  @moduledoc "Fetches a provider's JSON Web Key Set for agent identity verification."

  @callback fetch(String.t(), keyword()) :: {:ok, map()} | {:error, term()}

  @spec fetch(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch(uri, opts \\ []) when is_binary(uri) do
    finch = Keyword.get(opts, :finch, Ted.Finch)

    case Finch.request(Finch.build(:get, uri), finch, receive_timeout: 10_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        case JSON.decode(body) do
          {:ok, %{"keys" => keys} = document} when is_list(keys) -> {:ok, document}
          _invalid -> {:error, :invalid_jwks}
        end

      {:ok, %{status: status}} ->
        {:error, {:jwks_rejected, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
