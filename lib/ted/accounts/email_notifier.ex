defmodule Ted.Accounts.EmailNotifier do
  @moduledoc false

  import Swoosh.Email

  alias Ted.Accounts.User
  alias Ted.Mailer

  @callback deliver_verification(User.t(), String.t()) ::
              {:ok, Swoosh.Email.t()} | {:error, term()}

  @spec deliver_verification(User.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_verification(%User{} = user, url) when is_binary(url) do
    {from_name, from_address} =
      Application.get_env(:ted, :email_from, {"Ted", "hello@ted.pepicrft.me"})

    email =
      new()
      |> to(user.email)
      |> from({from_name, from_address})
      |> subject("Verify your Ted email")
      |> text_body("""
      Verify your Ted email

      Open this secure link, then confirm the address in your browser:
      #{url}

      The link expires in 15 minutes and can only be used once. If you did not create this account, ignore this message.
      """)

    with {:ok, _metadata} <- Mailer.deliver(email), do: {:ok, email}
  end
end
