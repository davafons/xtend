Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  root "people#index"

  # Core
  resources :people, only: [ :index, :show, :new, :create, :update ] do
    resource :pin, only: [ :create, :destroy ]
    resource :follow_protection, only: [ :create, :destroy ], controller: "follow/protections"
    resources :tags, only: [ :create, :destroy ], controller: "person_tags"
    resources :reminders, only: :create
    resource :card, only: :show, controller: "people/cards"
  end
  resources :drafts, except: :show do
    get :ideas, on: :collection
    scope module: :drafts do
      resources :alternatives, only: %i[ create destroy ] do
        resource :promotion, only: :create
      end
      resources :revisions, only: [] do
        resource :restoration, only: :create
      end
    end
  end
  resource :inbox, only: :show, controller: "inbox"
  resource :outreach, only: :show, controller: "outreach"
  resources :reminders, only: [ :update, :destroy ]
  resources :reply_events, only: [] do
    resource :dismissal, only: :create, controller: "reply_events/dismissals"
  end
  resource :network, only: :show, controller: "network"
  resource :timeline, only: :show, controller: "timeline"
  resource :insights, only: :show
  resource :week, only: :show
  resource :growth, only: %i[show update]
  namespace :growth do
    resource :check, only: %i[create destroy]
  end
  resource :search, only: :show
  resource :settings, only: [ :show, :update ]
  resource :appearance, only: :update

  # Follower snapshots and cleanup
  namespace :follow do
    resources :reviews, only: [ :index, :create ]
    resources :trials, only: :index
  end
  get "/follow/history", to: "follow/history#index", as: :follower_history

  # X API
  namespace :x do
    resources :sync_runs, only: [ :create, :update ]
    resource :sources, only: :show
    resources :billing_cycles, only: [ :index, :create, :update ]
    resources :archive_imports, only: :create
    resources :captures, only: :create
    get "captures/context", to: "contexts#show", as: :capture_context
    resource :capture_status, only: :show
    resource :connection, only: [ :create, :update, :destroy ] do
      get :callback
    end
  end

  # AI assistants
  get "/grok/connector", to: redirect("/ai/connector")
  namespace :ai do
    resource :connector, only: :show
    resources :proposals, only: :update do
      patch :review, on: :collection
      resource :undo, only: :create
    end
  end

  # Linking AI clients and the extension (OAuth 2.1). Discovery, registration, tokens, and revocation are reachable
  # outside Cloudflare Access; the approval page and connected apps are not.
  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get "/.well-known/oauth-protected-resource(/*resource)", to: "oauth/metadata#protected_resource", format: false
  namespace :oauth do
    get "authorize", to: "authorizations#new"
    post "authorize", to: "authorizations#create"
    post "token", to: "tokens#create"
    post "revoke", to: "tokens#revoke"
    post "register", to: "registrations#create"
    resources :grants, only: [ :create, :destroy ]
  end

  # MCP connector for any AI assistant
  post "/mcp", to: "mcp/endpoints#create", as: :mcp
  match "/mcp", to: "mcp/endpoints#unsupported", via: [ :get, :delete ]

  get "/favicon.ico", to: redirect("/icon.png")
  get "up" => "rails/health#show", as: :rails_health_check
end
