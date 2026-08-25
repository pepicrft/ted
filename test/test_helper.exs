ExUnit.start(max_cases: 10)

Ecto.Adapters.SQL.Sandbox.mode(Ted.Repo, :manual)
Mimic.copy(Ted.Index)
Mimic.copy(Ted.Accounts.EmailNotifier)
Mimic.copy(Ted.RateLimit)
Mimic.copy(Finch)
Mimic.copy(Ted.Telegram.Client)
