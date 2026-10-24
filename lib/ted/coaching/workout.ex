defmodule Ted.Coaching.Workout do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "workouts" do
    field(:performed_on, :date)
    field(:name, :string)
    field(:duration_minutes, :integer)
    field(:perceived_exertion, :integer)
    field(:movements, {:array, :map}, default: [])
    field(:notes, :string)
    field(:status, :string, default: "completed")
    field(:completed_sets, {:array, :map}, default: [])
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    belongs_to(:user, Ted.Accounts.User)
    belongs_to(:plan, Ted.Coaching.Plan)
    belongs_to(:workout_template, Ted.Coaching.WorkoutTemplate)

    field(:workout_template_version, :integer)

    timestamps()
  end

  def changeset(workout, attrs) do
    workout
    |> cast(attrs, [
      :user_id,
      :performed_on,
      :name,
      :duration_minutes,
      :perceived_exertion,
      :movements,
      :notes,
      :workout_template_id,
      :workout_template_version
    ])
    |> validate_required([:user_id, :performed_on, :name])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 480)
    |> validate_number(:perceived_exertion,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10
    )
    |> validate_length(:notes, max: 4_000)
    |> validate_number(:workout_template_version, greater_than: 0)
  end

  def set_changeset(attrs) do
    {%{},
     %{
       movement_id: :string,
       set_number: :integer,
       repetitions: :integer,
       load_kg: :float,
       perceived_exertion: :integer,
       pain: :integer,
       notes: :string
     }}
    |> cast(attrs, [
      :movement_id,
      :set_number,
      :repetitions,
      :load_kg,
      :perceived_exertion,
      :pain,
      :notes
    ])
    |> validate_required([:movement_id, :set_number, :repetitions])
    |> validate_number(:set_number, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_number(:repetitions, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:load_kg, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:perceived_exertion,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10
    )
    |> validate_number(:pain, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_length(:notes, max: 4_000)
  end

  def record_set_changeset(workout, attrs, safety_hold) do
    with {:ok, set} <- attrs |> set_changeset() |> apply_action(:insert) do
      set = Map.new(set, fn {key, value} -> {Atom.to_string(key), value} end)
      existing = Enum.find(workout.completed_sets, &same_set?(&1, set))

      cond do
        workout.status != "in_progress" ->
          {:error, :workout_not_in_progress}

        existing == set ->
          {:ok, change(workout)}

        progress(workout).safety_hold or safety_hold ->
          {:error, :safety_hold}

        not prescribed_set?(workout, set) ->
          {:error, :invalid_arguments}

        true ->
          sets = Enum.reject(workout.completed_sets, &same_set?(&1, set)) ++ [set]
          {:ok, change(workout, completed_sets: sets)}
      end
    end
  end

  def finish_changeset(workout, attrs, safety_hold) do
    status = attrs["status"]
    progress = progress(workout)

    cond do
      status not in ~w(completed cancelled) ->
        {:error, :invalid_arguments}

      workout.status == status ->
        {:ok, change(workout)}

      workout.status != "in_progress" ->
        {:error, :workout_not_in_progress}

      status == "cancelled" ->
        {:ok, finish_changes(workout, attrs)}

      progress.safety_hold or safety_hold ->
        {:error, :safety_hold}

      progress.remaining_sets > 0 ->
        {:error, :workout_incomplete}

      true ->
        {:ok, finish_changes(workout, attrs)}
    end
  end

  defp finish_changes(workout, attrs) do
    workout
    |> changeset(Map.take(attrs, ~w(duration_minutes perceived_exertion notes)))
    |> change(status: attrs["status"], completed_at: DateTime.utc_now())
  end

  defp same_set?(first, second),
    do:
      first["movement_id"] == second["movement_id"] and
        first["set_number"] == second["set_number"]

  defp prescribed_set?(workout, set) do
    Enum.any?(workout.movements, fn movement ->
      movement["id"] == set["movement_id"] and set["set_number"] <= movement["sets"]
    end)
  end

  def progress(workout) do
    prescribed_sets =
      for movement <- workout.movements,
          is_binary(movement["id"]),
          is_integer(movement["sets"]) and movement["sets"] > 0,
          set_number <- 1..movement["sets"] do
        %{movement: movement, set_number: set_number}
      end

    remaining =
      Enum.reject(prescribed_sets, fn prescribed ->
        Enum.any?(workout.completed_sets, fn actual ->
          actual["movement_id"] == prescribed.movement["id"] and
            actual["set_number"] == prescribed.set_number
        end)
      end)

    safety_hold = Enum.any?(workout.completed_sets, &((&1["pain"] || 0) >= 4))

    %{
      total_sets: length(prescribed_sets),
      completed_sets: length(prescribed_sets) - length(remaining),
      remaining_sets: length(remaining),
      next_set:
        if(workout.status == "in_progress" and not safety_hold, do: List.first(remaining)),
      safety_hold: safety_hold
    }
  end
end
