defmodule TedWeb.ApiAuth do
  @moduledoc "Authenticates auth.md bearer access tokens."

  import Plug.Conn

  alias Ted.AgentAuth
  alias Ted.Index
  alias TedWeb.PublicOrigin

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    required_scopes = Keyword.get(opts, :scopes, [])

    with {:ok, token} <- credential(conn),
         {:ok, authorization} <-
           AgentAuth.authorize(token, required_scopes,
             index: conn.private[:ted_index] || Index.context(),
             issuer: PublicOrigin.from_conn(conn),
             resource: requested_resource(conn)
           ) do
      assign(conn, :authorization, authorization)
    else
      {:error, :insufficient_scope} -> unauthorized(conn, "insufficient_scope", required_scopes)
      _error -> unauthorized(conn, "invalid_token", required_scopes)
    end
  end

  defp requested_resource(conn) do
    if String.starts_with?(conn.request_path, "/mcp"),
      do: PublicOrigin.from_conn(conn) <> "/mcp",
      else: PublicOrigin.from_conn(conn)
  end

  defp credential(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {:ok, token}
      _authorization -> {:error, :missing_token}
    end
  end

  defp unauthorized(conn, error, scopes) do
    metadata_path =
      if String.starts_with?(conn.request_path, "/mcp"),
        do: "/.well-known/oauth-protected-resource/mcp",
        else: "/.well-known/oauth-protected-resource"

    metadata = PublicOrigin.from_conn(conn) <> metadata_path

    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer resource_metadata="#{metadata}", error="#{error}", scope="#{Enum.join(scopes, " ")}")
    )
    |> put_resp_content_type("application/json")
    |> send_resp(401, JSON.encode!(%{error: error}))
    |> halt()
  end
end
