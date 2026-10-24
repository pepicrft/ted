defmodule TedWeb.ApiSchemas.Profile do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Profile",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        user_id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        timezone: %OpenApiSpex.Schema{type: :string},
        primary_goal: %OpenApiSpex.Schema{type: :string},
        experience_level: %OpenApiSpex.Schema{type: :string},
        training_days_per_week: %OpenApiSpex.Schema{type: :integer},
        session_minutes: %OpenApiSpex.Schema{type: :integer},
        equipment: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}},
        dietary_preferences: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :string}
        },
        daily_energy_target_kcal: %OpenApiSpex.Schema{type: :integer, nullable: true},
        daily_protein_target_g: %OpenApiSpex.Schema{type: :integer, nullable: true}
      }
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.CheckIn do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "CheckIn",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        date: %OpenApiSpex.Schema{type: :string, format: :date},
        weight_kg: %OpenApiSpex.Schema{type: :number, nullable: true},
        sleep_hours: %OpenApiSpex.Schema{type: :number, nullable: true},
        energy: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 5, nullable: true},
        soreness: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 5, nullable: true},
        pain: %OpenApiSpex.Schema{type: :integer, minimum: 0, maximum: 10, nullable: true},
        nutrition_adherence: %OpenApiSpex.Schema{
          type: :integer,
          minimum: 1,
          maximum: 5,
          nullable: true
        },
        note: %OpenApiSpex.Schema{type: :string, nullable: true}
      }
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.Workout do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Workout",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        performed_on: %OpenApiSpex.Schema{type: :string, format: :date},
        name: %OpenApiSpex.Schema{type: :string},
        status: %OpenApiSpex.Schema{type: :string},
        duration_minutes: %OpenApiSpex.Schema{type: :integer, nullable: true},
        perceived_exertion: %OpenApiSpex.Schema{type: :integer, nullable: true},
        movements: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}},
        completed_sets: %OpenApiSpex.Schema{type: :array, items: TedWeb.ApiSchemas.WorkoutSet},
        notes: %OpenApiSpex.Schema{type: :string, nullable: true},
        workout_template_id: %OpenApiSpex.Schema{type: :string, format: :uuid, nullable: true},
        workout_template_version: %OpenApiSpex.Schema{type: :integer, nullable: true},
        plan_id: %OpenApiSpex.Schema{type: :string, format: :uuid, nullable: true},
        started_at: %OpenApiSpex.Schema{type: :string, format: :date_time, nullable: true},
        completed_at: %OpenApiSpex.Schema{type: :string, format: :date_time, nullable: true},
        updated_at: %OpenApiSpex.Schema{type: :string, format: :date_time},
        progress: %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            total_sets: %OpenApiSpex.Schema{type: :integer, minimum: 0},
            completed_sets: %OpenApiSpex.Schema{type: :integer, minimum: 0},
            remaining_sets: %OpenApiSpex.Schema{type: :integer, minimum: 0},
            next_set: %OpenApiSpex.Schema{
              type: :object,
              nullable: true,
              properties: %{
                movement: TedWeb.ApiSchemas.WorkoutTemplateMovement,
                set_number: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 10}
              },
              required: [:movement, :set_number]
            },
            safety_hold: %OpenApiSpex.Schema{type: :boolean}
          },
          required: [:total_sets, :completed_sets, :remaining_sets, :next_set, :safety_hold]
        }
      }
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.StartWorkout do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Start workout",
      type: :object,
      properties: %{performed_on: %OpenApiSpex.Schema{type: :string, format: :date}},
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.WorkoutSet do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Workout set",
      type: :object,
      properties: %{
        movement_id: %OpenApiSpex.Schema{type: :string},
        set_number: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 10},
        repetitions: %OpenApiSpex.Schema{type: :integer, minimum: 0, maximum: 1_000},
        load_kg: %OpenApiSpex.Schema{type: :number, minimum: 0, maximum: 1_000},
        perceived_exertion: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 10},
        pain: %OpenApiSpex.Schema{type: :integer, minimum: 0, maximum: 10},
        notes: %OpenApiSpex.Schema{type: :string}
      },
      required: [:movement_id, :set_number, :repetitions],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.FinishWorkout do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Finish workout",
      type: :object,
      properties: %{
        status: %OpenApiSpex.Schema{type: :string, enum: ["completed", "cancelled"]},
        duration_minutes: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 480},
        perceived_exertion: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 10},
        notes: %OpenApiSpex.Schema{type: :string}
      },
      required: [:status],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.BuildPlan do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Build plan",
      description:
        "Snapshots the selected templates in the supplied order. Omitting workout_template_ids preserves active plan assignments or leaves the plan unconfigured.",
      type: :object,
      properties: %{
        date: %OpenApiSpex.Schema{type: :string, format: :date},
        workout_template_ids: %OpenApiSpex.Schema{
          type: :array,
          minItems: 1,
          maxItems: 14,
          uniqueItems: true,
          items: %OpenApiSpex.Schema{type: :string, format: :uuid}
        }
      },
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.WorkoutTemplate do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Workout template",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        name: %OpenApiSpex.Schema{type: :string},
        description: %OpenApiSpex.Schema{type: :string, nullable: true},
        estimated_duration_minutes: %OpenApiSpex.Schema{type: :integer, nullable: true},
        movements: %OpenApiSpex.Schema{
          type: :array,
          items: TedWeb.ApiSchemas.WorkoutTemplateMovement
        },
        image_url: %OpenApiSpex.Schema{type: :string},
        image_alt: %OpenApiSpex.Schema{type: :string},
        version: %OpenApiSpex.Schema{type: :integer}
      },
      required: [:name, :movements, :image_url, :image_alt]
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.WorkoutTemplateMovement do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Workout template movement",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string},
        name: %OpenApiSpex.Schema{type: :string},
        sets: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 10},
        repetitions: %OpenApiSpex.Schema{type: :string},
        rest_seconds: %OpenApiSpex.Schema{type: :integer, minimum: 0, maximum: 900},
        instructions: %OpenApiSpex.Schema{type: :string},
        image_url: %OpenApiSpex.Schema{type: :string},
        image_alt: %OpenApiSpex.Schema{type: :string},
        video_url: %OpenApiSpex.Schema{type: :string}
      },
      required: [
        :id,
        :name,
        :sets,
        :repetitions,
        :rest_seconds,
        :instructions,
        :image_url,
        :image_alt,
        :video_url
      ]
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.Meal do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Meal",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        occurred_at: %OpenApiSpex.Schema{type: :string, format: :date_time},
        description: %OpenApiSpex.Schema{type: :string},
        energy_kcal: %OpenApiSpex.Schema{type: :integer, nullable: true},
        protein_g: %OpenApiSpex.Schema{type: :number, nullable: true},
        carbohydrate_g: %OpenApiSpex.Schema{type: :number, nullable: true},
        fat_g: %OpenApiSpex.Schema{type: :number, nullable: true}
      }
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.GenericObject do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{title: "GenericObject", type: :object, additionalProperties: true},
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.Status do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Status",
      type: :object,
      properties: %{status: %OpenApiSpex.Schema{type: :string}},
      required: [:status]
    },
    derive?: false
  )
end

defmodule TedWeb.ApiSchemas.Error do
  @moduledoc false
  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Error",
      type: :object,
      properties: %{error: %OpenApiSpex.Schema{type: :string}},
      required: [:error]
    },
    derive?: false
  )
end
