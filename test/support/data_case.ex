defmodule Ted.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Ted.Repo

  using do
    quote do
      use Mimic
    end
  end

  setup do
    sandbox_owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(sandbox_owner) end)
    {:ok, repo: Repo}
  end

  @spec endpoint_conn(atom(), String.t(), term(), String.t() | nil, keyword()) :: Plug.Conn.t()
  def endpoint_conn(
        method,
        path,
        body,
        authorization \\ nil,
        rate_limits \\ unrestricted_rate_limits()
      ) do
    conn =
      case body do
        nil -> Plug.Test.conn(method, path)
        body when is_binary(body) -> Plug.Test.conn(method, path, body)
        body -> Plug.Test.conn(method, path, JSON.encode!(body))
      end

    conn
    |> Plug.Conn.put_private(:ted_index, Repo)
    |> Plug.Conn.put_private(:ted_rate_limit_namespace, System.unique_integer([:positive]))
    |> Plug.Conn.put_private(:ted_rate_limits, rate_limits)
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> maybe_json_content_type(body)
    |> maybe_authorize(authorization)
    |> TedWeb.Endpoint.call([])
  end

  defp maybe_json_content_type(conn, nil), do: conn

  defp maybe_json_content_type(conn, _body),
    do: Plug.Conn.put_req_header(conn, "content-type", "application/json")

  defp maybe_authorize(conn, nil), do: conn

  defp maybe_authorize(conn, access_token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{access_token}")

  defp unrestricted_rate_limits do
    [
      website: [scale_ms: 60_000, limit: 100_000],
      documentation: [scale_ms: 60_000, limit: 100_000],
      api: [scale_ms: 60_000, limit: 100_000],
      authentication: [scale_ms: 60_000, limit: 100_000],
      model_context_protocol: [scale_ms: 60_000, limit: 100_000]
    ]
  end
end
