Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  root "today#index"

  # Core CRM
  resources :people, only: [ :index, :show, :new, :create, :update ] do
    resource :pin, only: [ :create, :destroy ]
    resource :follow_protection, only: [ :create, :destroy ], controller: "follow/protections"
    resources :tags, only: [ :create, :destroy ], controller: "person_tags"
  end
  resources :posts, only: [] do
    resource :disposition, only: [ :create, :destroy ], controller: "post_dispositions"
    resource :reply_report, only: [ :create, :destroy ]
  end
  resources :drafts, except: :show do
    get :ideas, on: :collection
  end
  resource :daily_session, only: :update
  resource :settings, only: [ :show, :update ]
  resource :discovery, only: :show
  resource :context_export, only: :show

  # Follower snapshots and cleanup
  namespace :follow do
    resources :reviews, only: [ :index, :create ]
  end
  get "/follow/history", to: "follow/history#index", as: :follower_history

  # Discovery of reply targets
  namespace :discovery do
    resources :suggestions, only: :create do
      post :refresh, on: :collection
    end
    resources :imports, only: :create
  end

  # X API
  namespace :x do
    resources :sync_runs, only: [ :create, :update ]
    resource :sources, only: :show
    resources :billing_cycles, only: [ :index, :create, :update ]
    resources :archive_imports, only: :create
    resource :connection, only: [ :create, :update, :destroy ] do
      get :callback
    end
    resource :client_configuration, only: :update
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
