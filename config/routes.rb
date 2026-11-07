Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  root "people#index"

  # Core CRM
  resources :people, only: [ :index, :show, :new, :create, :update ] do
    resource :pin, only: [ :create, :destroy ]
    resource :follow_protection, only: [ :create, :destroy ], controller: "follow/protections"
    resources :tags, only: [ :create, :destroy ], controller: "person_tags"
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
  resource :settings, only: [ :show, :update ]
  resource :context_export, only: :show

  # Follower snapshots and cleanup
  namespace :follow do
    resources :reviews, only: [ :index, :create ]
  end
  get "/follow/history", to: "follow/history#index", as: :follower_history

  # X API
  namespace :x do
    resources :sync_runs, only: [ :create, :update ]
    resource :sources, only: :show
    resources :billing_cycles, only: [ :index, :create, :update ]
    resources :archive_imports, only: :create
    resources :captures, only: :create
    resource :capture_token, only: [ :create, :destroy ]
    resource :connection, only: [ :create, :update, :destroy ] do
      get :callback
    end
  end

  # Grok Bot
  namespace :grok do
    resource :connector, only: :show
    resources :intakes, only: :create
    resources :proposals, only: :update do
      patch :review, on: :collection
    end
  end

  # MCP connector for Grok Bot
  namespace :mcp do
    resource :token, only: [ :create, :destroy ]
  end
  post "/mcp", to: "mcp/endpoints#create", as: :mcp
  match "/mcp", to: "mcp/endpoints#unsupported", via: [ :get, :delete ]

  get "/favicon.ico", to: redirect("/icon.svg")
  get "up" => "rails/health#show", as: :rails_health_check
end
