defmodule Ted.TelegramTest do
  use Ted.DataCase, async: true

  alias Ted.Accounts
  alias Ted.Coaching
  alias Ted.Telegram
  alias Ted.Telegram.Connection

  test "the eat command returns concrete, cited suggestions from the shared coach", %{repo: repo} do
    assert {:ok, user} =
             Accounts.create_user(%{"email" => "telegram@example.test", "name" => "Jamie"}, repo)

    assert {:ok, _profile} =
             Coaching.update_profile(
               user.id,
               %{
                 "primary_goal" => "fat_loss",
                 "dietary_preferences" => ["vegetarian"],
                 "daily_protein_target_g" => 140
               },
               repo
             )

    assert {:ok, _connection} =
             repo.insert(
               Connection.changeset(%Connection{}, %{
                 user_id: user.id,
                 telegram_user_id: "42",
                 chat_id: "99",
                 username: "jamie"
               })
             )

    expect(Ted.Telegram.Client, :send_message, fn "test-token", "99", reply ->
      assert reply =~ "concrete option"
      assert reply =~ "Tofu and edamame grain bowl"
      assert reply =~ "Why these suggestions"
      assert reply =~ "https://pubmed.ncbi.nlm.nih.gov/28698222/"
      assert reply =~ "general educational suggestions"
      :ok
    end)

    assert :ok =
             Telegram.handle_update(
               %{
                 "message" => %{
                   "text" => "/eat dinner 20",
                   "chat" => %{"id" => 99},
                   "from" => %{"id" => 42, "first_name" => "Jamie", "username" => "jamie"}
                 }
               },
               repo: repo,
               client: Ted.Telegram.Client,
               telegram: [bot_token: "test-token"]
             )
  end
end
