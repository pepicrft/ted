defmodule TedWeb.LegalController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias TedWeb.LegalPage

  tags ["Website"]
  security []

  operation :terms,
    operation_id: "terms_of_service",
    summary: "Read the terms of service",
    responses: [ok: {"Terms of service", "text/html", %Schema{type: :string}}]

  operation :privacy,
    operation_id: "privacy_policy",
    summary: "Read the privacy policy",
    responses: [ok: {"Privacy policy", "text/html", %Schema{type: :string}}]

  operation :cookies,
    operation_id: "cookie_terms",
    summary: "Read the cookie terms",
    responses: [ok: {"Cookie terms", "text/html", %Schema{type: :string}}]

  def terms(conn, _params), do: send_page(conn, LegalPage.terms(legal(conn), page_opts(conn)))
  def privacy(conn, _params), do: send_page(conn, LegalPage.privacy(legal(conn), page_opts(conn)))
  def cookies(conn, _params), do: send_page(conn, LegalPage.cookies(legal(conn), page_opts(conn)))

  defp page_opts(conn) do
    [base_url: TedWeb.PublicOrigin.from_conn(conn)]
  end

  defp send_page(conn, page) do
    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    )
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, page)
  end

  defp legal(conn), do: conn.private[:ted_legal] || Application.fetch_env!(:ted, :legal)
end
