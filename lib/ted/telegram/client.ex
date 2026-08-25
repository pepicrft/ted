defmodule Ted.Telegram.Client do
  @moduledoc "Sends messages through the Telegram Bot application programming interface."

  @callback send_message(String.t(), String.t(), String.t()) :: :ok | {:error, term()}

  @spec send_message(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_message(token, chat_id, text)
      when is_binary(token) and is_binary(chat_id) and is_binary(text) do
    request =
      Finch.build(
        :post,
        "https://api.telegram.org/bot#{token}/sendMessage",
        [{"content-type", "application/json"}],
        JSON.encode!(%{chat_id: chat_id, text: text})
      )

    case Finch.request(request, Ted.Finch) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:telegram_rejected, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def send_message(_token, _chat_id, _text), do: {:error, :telegram_not_configured}
end
