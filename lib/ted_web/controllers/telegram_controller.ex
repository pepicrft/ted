defmodule TedWeb.TelegramController do
  use TedWeb, :controller

  alias Ted.Telegram

  def webhook(conn, params) do
    with {:ok, configured_secret} <- configured_secret(),
         :ok <- verify_secret(conn, configured_secret),
         :ok <- Telegram.handle_update(params) do
      send_resp(conn, 204, "")
    else
      {:error, :telegram_not_configured} ->
        conn |> put_status(503) |> json(%{error: "telegram_not_configured"})

      {:error, :invalid_secret} ->
        conn |> put_status(401) |> json(%{error: "invalid_secret"})

      {:error, :unsupported_update} ->
        send_resp(conn, 204, "")

      {:error, _reason} ->
        conn |> put_status(500) |> json(%{error: "telegram_update_failed"})
    end
  end

  defp configured_secret do
    case Application.get_env(:ted, :telegram, []) |> Keyword.get(:webhook_secret) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _value -> {:error, :telegram_not_configured}
    end
  end

  defp verify_secret(conn, configured_secret) do
    case get_req_header(conn, "x-telegram-bot-api-secret-token") do
      [provided] when byte_size(provided) == byte_size(configured_secret) ->
        if Plug.Crypto.secure_compare(provided, configured_secret),
          do: :ok,
          else: {:error, :invalid_secret}

      _headers ->
        {:error, :invalid_secret}
    end
  end
end
