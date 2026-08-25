defmodule TedWeb.Router do
  use TedWeb, :router

  pipeline :documented do
    plug :accepts, ["json"]
    plug TedWeb.RateLimit, bucket: :api
    plug OpenApiSpex.Plug.PutApiSpec, module: TedWeb.ApiSpec
  end

  pipeline :website do
    plug TedWeb.RateLimit, bucket: :website, response: :text
    plug OpenApiSpex.Plug.PutApiSpec, module: TedWeb.ApiSpec
  end

  pipeline :reference do
    plug TedWeb.RateLimit, bucket: :documentation, response: :text
    plug OpenApiSpex.Plug.PutApiSpec, module: TedWeb.ApiSpec
  end

  pipeline :authentication do
    plug :accepts, ["json"]
    plug TedWeb.RateLimit, bucket: :authentication
  end

  pipeline :telegram do
    plug :accepts, ["json"]
    plug TedWeb.RateLimit, bucket: :authentication
  end

  pipeline :mcp do
    plug TedWeb.RateLimit, bucket: :model_context_protocol
    plug TedWeb.ValidateMcpOrigin
    plug TedWeb.ApiAuth, scopes: ["mcp"]
  end

  pipeline :agent_claim do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TedWeb.RateLimit, bucket: :authentication, response: :text
  end

  scope "/", TedWeb do
    pipe_through :website

    get "/", HomeController, :show
    get "/terms", LegalController, :terms
    get "/privacy", LegalController, :privacy
    get "/cookies", LegalController, :cookies
  end

  scope "/", TedWeb do
    pipe_through :reference
    get "/docs", ApiReferenceController, :show
    get "/auth.md", AuthMarkdownController, :show
  end

  scope "/", TedWeb do
    pipe_through :documented

    get "/health", HealthController, :show
    get "/openapi.json", OpenApiController, :show
    get "/api/profile", CoachingController, :get_profile
    put "/api/profile", CoachingController, :update_profile
    post "/api/check-ins", CoachingController, :record_check_in
    post "/api/workouts", CoachingController, :log_workout
    post "/api/meals", CoachingController, :log_meal
    post "/api/meal-recommendations", CoachingController, :recommend_meal
    get "/api/objectives", CoachingController, :list_objectives
    put "/api/objectives", CoachingController, :set_objective
    get "/api/plan", CoachingController, :get_active_plan
    post "/api/plan", CoachingController, :build_plan
    post "/api/plan/reviews", CoachingController, :review_plan
    get "/api/today", CoachingController, :get_today_plan
    get "/api/progress", CoachingController, :get_progress
  end

  scope "/", TedWeb do
    pipe_through :authentication

    get "/.well-known/oauth-protected-resource", DiscoveryController, :protected_resource
    get "/.well-known/oauth-protected-resource/mcp", DiscoveryController, :mcp_protected_resource
    get "/.well-known/oauth-authorization-server", DiscoveryController, :authorization_server
    get "/.well-known/jwks.json", DiscoveryController, :jwks
    get "/.well-known/mcp/server-card.json", DiscoveryController, :mcp_server_card
    post "/agent/identity", AgentIdentityController, :create
    post "/agent/identity/claim", AgentIdentityController, :claim
    post "/agent/event/notify", DiscoveryController, :event_notify
    post "/oauth2/token", OAuthController, :token
    post "/oauth2/revoke", OAuthController, :revoke
  end

  scope "/", TedWeb do
    pipe_through :telegram
    post "/telegram/webhook", TelegramController, :webhook
  end

  scope "/", TedWeb do
    pipe_through :agent_claim

    get "/agent/identity/claim", ClaimController, :show
    post "/agent/identity/claim/sign-up", ClaimController, :sign_up
    post "/agent/identity/claim/sign-in", ClaimController, :sign_in
    get "/agent/identity/claim/verify-email", ClaimController, :show_email_verification
    post "/agent/identity/claim/verify-email", ClaimController, :verify_email

    post "/agent/identity/claim/resend-email-verification",
         ClaimController,
         :resend_email_verification

    post "/agent/identity/claim/confirm", ClaimController, :confirm
    post "/agent/identity/claim/sign-out", ClaimController, :sign_out
  end

  scope "/" do
    pipe_through :mcp
    forward "/mcp", Ted.MCP
  end
end
