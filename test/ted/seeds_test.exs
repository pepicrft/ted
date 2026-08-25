defmodule Ted.SeedsTest do
  use Ted.DataCase, async: true

  import Ecto.Query

  alias Ted.Accounts.User
  alias Ted.Coaching.{CheckIn, Meal, Objective, Plan, Profile, Workout}

  @seed_path Path.expand("../../priv/repo/seeds.exs", __DIR__)
  @seed_user_ids [
    "00000000-0000-0000-0000-000000000001",
    "00000000-0000-0000-0000-000000000002"
  ]

  test "the development seed is idempotent", %{repo: repo} do
    Code.eval_file(@seed_path)
    initial_counts = seed_counts(repo)

    Code.eval_file(@seed_path)

    assert initial_counts == %{
             users: 2,
             profiles: 2,
             check_ins: 1,
             workouts: 1,
             meals: 1,
             objectives: 2,
             plans: 2
           }

    assert seed_counts(repo) == initial_counts
  end

  defp seed_counts(repo) do
    %{
      users: count(repo, User, :id),
      profiles: count(repo, Profile, :user_id),
      check_ins: count(repo, CheckIn, :user_id),
      workouts: count(repo, Workout, :user_id),
      meals: count(repo, Meal, :user_id),
      objectives: count(repo, Objective, :user_id),
      plans: count(repo, Plan, :user_id)
    }
  end

  defp count(repo, schema, field) do
    repo.aggregate(
      from(record in schema, where: field(record, ^field) in ^@seed_user_ids),
      :count
    )
  end
end
