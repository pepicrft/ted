defmodule Ted.Coaching.WorkoutTemplate do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "workout_templates" do
    field(:name, :string)
    field(:description, :string)
    field(:estimated_duration_minutes, :integer)
    field(:movements, {:array, :map}, default: [])
    field(:image_url, :string)
    field(:image_alt, :string)
    field(:version, :integer, default: 1)

    belongs_to(:user, Ted.Accounts.User)
    has_many(:workouts, Ted.Coaching.Workout)

    timestamps()
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :user_id,
      :name,
      :description,
      :estimated_duration_minutes,
      :movements,
      :image_url,
      :image_alt,
      :version
    ])
    |> validate_required([:user_id, :name, :movements, :image_url, :image_alt, :version])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:description, max: 2_000)
    |> validate_number(:estimated_duration_minutes, greater_than: 0, less_than_or_equal_to: 480)
    |> validate_length(:movements, min: 1, max: 12)
    |> validate_length(:image_url, min: 1, max: 2_000)
    |> validate_format(:image_url, ~r{\A(?:/assets/|https://)})
    |> validate_length(:image_alt, min: 1, max: 280)
    |> validate_number(:version, greater_than: 0)
    |> validate_movements()
  end

  defp validate_movements(changeset) do
    validate_change(changeset, :movements, fn :movements, movements ->
      case movements_error(movements) do
        nil -> []
        error -> [movements: error]
      end
    end)
  end

  defp movements_error(movements) do
    if Enum.all?(movements, &is_map/1) do
      ids = Enum.map(movements, &Map.get(&1, "id"))

      cond do
        Enum.any?(movements, &(not valid_movement?(&1))) ->
          "must include a unique id, name, sets, repetitions, rest_seconds, instructions, image_url, image_alt, and video_url for each movement"

        Enum.uniq(ids) != ids ->
          "must use a unique id for each movement"

        true ->
          nil
      end
    else
      "must contain objects"
    end
  end

  defp valid_movement?(movement) do
    valid_movement_identity?(movement) and
      valid_movement_configuration?(movement) and
      valid_movement_visual?(movement)
  end

  defp valid_movement_identity?(movement),
    do: string_in_range?(movement["id"], 1, 100) and string_in_range?(movement["name"], 1, 160)

  defp valid_movement_configuration?(movement) do
    is_integer(movement["sets"]) and movement["sets"] in 1..10 and
      string_in_range?(movement["repetitions"], 1, 80) and
      is_integer(movement["rest_seconds"]) and movement["rest_seconds"] in 0..900 and
      string_in_range?(movement["instructions"], 1, 1_000)
  end

  defp valid_movement_visual?(movement),
    do:
      valid_image_url?(movement["image_url"]) and
        string_in_range?(movement["image_alt"], 1, 280) and
        valid_video_url?(movement["video_url"])

  defp valid_image_url?(value) when is_binary(value),
    do: String.match?(value, ~r{\A(?:/assets/|https://)})

  defp valid_image_url?(_value), do: false

  defp valid_video_url?(value) when is_binary(value),
    do: String.length(value) in 1..2_000 and String.match?(value, ~r{\Ahttps://})

  defp valid_video_url?(_value), do: false

  defp string_in_range?(value, minimum, maximum) when is_binary(value),
    do: String.length(value) in minimum..maximum

  defp string_in_range?(_value, _minimum, _maximum), do: false
end
