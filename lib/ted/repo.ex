defmodule Ted.Repo do
  use Ecto.Repo,
    otp_app: :ted,
    adapter: Ecto.Adapters.Postgres
end
