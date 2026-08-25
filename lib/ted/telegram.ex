defmodule Ted.Telegram do
  @moduledoc "Turns Telegram messages into the same coaching operations used by other clients."

  alias Ted.Accounts.User
  alias Ted.Coaching
  alias Ted.Repo
  alias Ted.Telegram.Connection

  @spec handle_update(map(), keyword()) :: :ok | {:error, term()}
  def handle_update(update, opts \\ [])

  def handle_update(update, opts) when is_map(update) do
    with {:ok, message} <- message(update),
         {:ok, user_id} <- find_or_create_user(message, repo(opts)),
         {:ok, reply} <- command(message.text, user_id, repo(opts)) do
      send_reply(message.chat_id, reply, opts)
    end
  end

  def handle_update(_update, _opts), do: {:error, :invalid_update}

  defp message(%{
         "message" => %{
           "text" => text,
           "chat" => %{"id" => chat_id},
           "from" => %{"id" => telegram_user_id} = from
         }
       })
       when is_binary(text) do
    name =
      [Map.get(from, "first_name"), Map.get(from, "last_name")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> case do
        "" -> "Telegram member"
        value -> value
      end

    {:ok,
     %{
       text: String.trim(text),
       chat_id: to_string(chat_id),
       telegram_user_id: to_string(telegram_user_id),
       username: Map.get(from, "username"),
       name: name
     }}
  end

  defp message(_update), do: {:error, :unsupported_update}

  defp find_or_create_user(message, repo) do
    case repo.get_by(Connection, telegram_user_id: message.telegram_user_id) do
      %Connection{} = connection ->
        maybe_update_chat(connection, message, repo)

      nil ->
        create_telegram_user(message, repo)
    end
  end

  defp maybe_update_chat(connection, message, repo) do
    connection
    |> Connection.changeset(%{chat_id: message.chat_id, username: message.username})
    |> repo.update()
    |> case do
      {:ok, connection} -> {:ok, connection.user_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_telegram_user(message, repo) do
    repo.transaction(fn ->
      with {:ok, user} <- repo.insert(User.changeset(%User{}, %{name: message.name})),
           {:ok, _connection} <-
             repo.insert(
               Connection.changeset(%Connection{}, %{
                 user_id: user.id,
                 telegram_user_id: message.telegram_user_id,
                 chat_id: message.chat_id,
                 username: message.username
               })
             ) do
        user.id
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp command(text, user_id, repo) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> execute_command(text, user_id, repo)
  end

  defp execute_command(["/start" | _arguments], _text, _user_id, _repo),
    do: {:ok, welcome()}

  defp execute_command(["/help"], _text, _user_id, _repo), do: {:ok, help()}

  defp execute_command(["/profile", goal, days], _text, user_id, repo) do
    case Integer.parse(days) do
      {training_days, ""} ->
        Coaching.update_profile(
          user_id,
          %{"primary_goal" => goal, "training_days_per_week" => training_days},
          repo
        )
        |> reply_with("Profile updated. Use /today for the plan.")

      _invalid ->
        {:ok, "Use /profile <goal> <days>, for example /profile strength 3."}
    end
  end

  defp execute_command(["/checkin", weight, energy, soreness], _text, user_id, repo) do
    Coaching.record_check_in(
      user_id,
      %{"weight_kg" => weight, "energy" => energy, "soreness" => soreness},
      repo
    )
    |> reply_with("Check-in saved. Thanks for the honest signal.")
  end

  defp execute_command(["/workout", minutes, effort], _text, user_id, repo) do
    Coaching.log_workout(
      user_id,
      %{
        "name" => "Strength session",
        "duration_minutes" => minutes,
        "perceived_exertion" => effort
      },
      repo
    )
    |> reply_with("Workout saved. Consistency beats heroics.")
  end

  defp execute_command(["/meal", energy, protein], text, user_id, repo) do
    description = String.replace_prefix(text, "/meal #{energy} #{protein}", "") |> String.trim()
    description = if description == "", do: "Meal", else: description

    Coaching.log_meal(
      user_id,
      %{"energy_kcal" => energy, "protein_g" => protein, "description" => description},
      repo
    )
    |> reply_with("Meal saved. One useful choice at a time.")
  end

  defp execute_command(["/eat"], _text, user_id, repo),
    do: recommend_meal(user_id, %{}, repo)

  defp execute_command(["/eat", meal_type], _text, user_id, repo),
    do: recommend_meal(user_id, %{"meal_type" => meal_type}, repo)

  defp execute_command(["/eat", meal_type, minutes], _text, user_id, repo) do
    case Integer.parse(minutes) do
      {time_available, ""} ->
        recommend_meal(
          user_id,
          %{"meal_type" => meal_type, "time_available_minutes" => time_available},
          repo
        )

      _invalid ->
        {:ok, "Use /eat, /eat <meal type>, or /eat <meal type> <minutes>."}
    end
  end

  defp execute_command(["/goal", kind, target, unit | label_parts], _text, user_id, repo) do
    label =
      if label_parts == [], do: String.replace(kind, "_", " "), else: Enum.join(label_parts, " ")

    with {:ok, _objective} <-
           Coaching.set_objective(
             user_id,
             %{
               "kind" => kind,
               "label" => label,
               "target_value" => target,
               "unit" => unit,
               "priority" => 5
             },
             repo
           ),
         {:ok, plan} <- Coaching.build_plan(user_id, Date.utc_today(), repo) do
      {:ok,
       "Objective saved and plan version #{plan.version} built. Use /today for today's focus."}
    else
      {:error, %Ecto.Changeset{}} ->
        {:ok, "I could not read that objective. Use /goal <kind> <target> <unit> <label>."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_command(["/plan"], _text, user_id, repo) do
    case Coaching.active_plan(user_id, repo) do
      {:ok, plan} -> {:ok, format_active_plan(plan)}
      {:error, :not_found} -> {:ok, "No active plan yet. Add an objective with /goal first."}
    end
  end

  defp execute_command(["/review"], _text, user_id, repo) do
    case Coaching.review_plan(user_id, Date.utc_today(), repo) do
      {:ok, review} ->
        {:ok, format_review(review)}

      {:error, :not_found} ->
        {:ok, "No active plan to review. Add an objective with /goal first."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_command(["/today"], _text, user_id, repo) do
    with {:ok, plan} <- Coaching.today_plan(user_id, Date.utc_today(), repo) do
      {:ok, format_plan(plan)}
    end
  end

  defp execute_command(_arguments, _text, _user_id, _repo), do: {:ok, help()}

  defp recommend_meal(user_id, arguments, repo) do
    case Coaching.recommend_meal(user_id, arguments, repo) do
      {:ok, recommendation} -> {:ok, format_meal_recommendation(recommendation)}
      {:error, :invalid_arguments} -> {:ok, "Use /eat, /eat dinner, or /eat dinner 20."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reply_with({:ok, _record}, message), do: {:ok, message}

  defp reply_with({:error, %Ecto.Changeset{}}, _message),
    do: {:ok, "I could not read that. Check the values and try again."}

  defp reply_with({:error, reason}, _message), do: {:error, reason}

  defp send_reply(chat_id, reply, opts) do
    telegram = Keyword.get(opts, :telegram, Application.get_env(:ted, :telegram, []))
    token = Keyword.get(telegram, :bot_token)
    client = Keyword.get(opts, :client, Ted.Telegram.Client)
    client.send_message(token, chat_id, reply)
  end

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)

  defp welcome do
    """
    Welcome to Ted. I keep your strength and nutrition coaching grounded in what you record.

    Start with /profile strength 3 and /goal strength 100 kg deadlift. Then use /checkin, /workout, /meal, /eat, and /today. Use /help for examples.
    """
    |> String.trim()
  end

  defp help do
    """
    Commands:
    /profile strength 3
    /goal fat_loss 78 kg Reach a steady body weight
    /checkin 82.5 4 2
    /workout 45 7
    /meal 650 45 chicken, rice, and vegetables
    /eat dinner 20
    /today
    /plan
    /review

    Goal kinds: fat_loss, muscle_gain, body_recomposition, strength, consistency.
    Check-in scores run from 1 to 5. Workout effort runs from 1 to 10.
    """
    |> String.trim()
  end

  defp format_plan(plan) do
    instructions = Enum.map_join(plan.training.instructions, "\n", &"• #{&1}")

    """
    #{plan.message}

    Readiness: #{plan.readiness.label} (#{plan.readiness.score}/100)
    #{plan.training.title}, about #{plan.training.duration_minutes} minutes
    #{instructions}

    Nutrition: #{plan.nutrition.guidance}
    """
    |> String.trim()
  end

  defp format_meal_recommendation(recommendation) do
    suggestions =
      Enum.map_join(recommendation.suggestions, "\n", fn suggestion ->
        "• #{suggestion.name}: #{suggestion.ingredients}"
      end)

    evidence =
      recommendation.evidence
      |> Enum.take(2)
      |> Enum.map_join("\n", &"• #{&1.title}: #{&1.url}")

    """
    #{recommendation.guidance}

    #{suggestions}

    Why these suggestions:
    #{evidence}

    These are general educational suggestions, not medical or dietetic care. Check allergens and medically restricted ingredients yourself.
    """
    |> String.trim()
  end

  defp format_active_plan(plan) do
    "Plan version #{plan.version} runs from #{plan.starts_on} to its review on #{plan.review_on}. " <>
      Enum.join(plan.rationale, " ")
  end

  defp format_review(review) do
    next = if review.next_plan, do: " New plan version: #{review.next_plan.version}.", else: ""
    summary = review.decision["summary"]

    "Review: #{summary} Confidence: #{review.confidence}.#{next}"
  end
end
