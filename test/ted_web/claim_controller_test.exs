defmodule TedWeb.ClaimControllerTest do
  use Ted.DataCase, async: true

  alias Ted.Accounts
  alias Ted.Accounts.EmailNotifier
  alias Ted.AgentAuth
  alias TedWeb.ClaimController

  test "a new person can complete the email claim flow", %{repo: repo} do
    auth_options = [
      index: repo,
      issuer: "http://www.example.com",
      api_key: "test",
      allow_ephemeral_signing_key: true
    ]

    assert {:ok, registration} =
             AgentAuth.create_service_registration("new-person@example.test", auth_options)

    stub(EmailNotifier, :deliver_verification, fn user, url ->
      send(self(), {:verification_email, user.email, url})
      {:ok, %Swoosh.Email{}}
    end)

    sign_up =
      registration.claim_attempt_token
      |> claim_conn(repo)
      |> ClaimController.sign_up(%{
        "claim_attempt_token" => registration.claim_attempt_token,
        "name" => "New Person",
        "password" => "a-realistic-test-passphrase"
      })

    assert sign_up.status == 303
    assert {:ok, user} = Accounts.get_user_by_email("new-person@example.test", repo)
    assert is_nil(user.email_verified_at)
    assert_receive {:verification_email, "new-person@example.test", verification_url}

    verification_params =
      verification_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    verified =
      registration.claim_attempt_token
      |> claim_conn(repo, user.id)
      |> ClaimController.verify_email(verification_params)

    assert verified.status == 303

    confirmed =
      registration.claim_attempt_token
      |> claim_conn(repo, user.id)
      |> ClaimController.confirm(%{
        "claim_attempt_token" => registration.claim_attempt_token,
        "user_code" => registration.user_code
      })

    assert confirmed.status == 200, confirmed.resp_body
    assert confirmed.resp_body =~ "Access confirmed"
    assert {:ok, token} = AgentAuth.exchange_claim(registration.claim_token, auth_options)
    assert "profile:write" in String.split(token.scope)
  end

  defp claim_conn(claim_attempt_token, repo, user_id \\ nil) do
    session = if user_id, do: %{ted_user_id: user_id}, else: %{}

    :post
    |> Plug.Test.conn("/agent/identity/claim")
    |> Plug.Test.init_test_session(session)
    |> Plug.Conn.put_private(:ted_index, repo)
    |> Plug.Conn.put_private(:ted_api_key, "test")
    |> Plug.Conn.put_private(:ted_email_notifier, EmailNotifier)
    |> Map.put(:query_params, %{"claim_attempt_token" => claim_attempt_token})
  end
end
