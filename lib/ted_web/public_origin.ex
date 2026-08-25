defmodule TedWeb.PublicOrigin do
  @moduledoc "Resolves the externally visible origin used in discovery and authentication documents."

  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(conn), do: conn.private[:ted_public_origin] || default()

  @spec default() :: String.t()
  def default, do: TedWeb.Endpoint.url()
end
