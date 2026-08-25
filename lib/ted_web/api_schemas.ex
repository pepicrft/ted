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
        duration_minutes: %OpenApiSpex.Schema{type: :integer, nullable: true},
        perceived_exertion: %OpenApiSpex.Schema{type: :integer, nullable: true},
        movements: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}},
        notes: %OpenApiSpex.Schema{type: :string, nullable: true}
      }
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
