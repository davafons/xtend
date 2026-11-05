Rails.application.routes.draw do
  root "today#index"
  get "/follower_history", to: "follower_history#index", as: :follower_history
  resources :people, only: [ :index, :show, :new, :create, :update ] do
    resource :pin, only: [ :create, :destroy ]
    resource :follow_protection, only: [ :create, :destroy ]
  end
  resources :posts, only: [] do
    resource :disposition, only: [ :create, :destroy ], controller: "post_dispositions"
    resource :reply_report, only: [ :create, :destroy ]
  end
  resources :follow_reviews, only: [ :index, :create ]
  resources :drafts, except: :show do
    get :ideas, on: :collection
  end
  resources :discovery_suggestions, only: :create do
    post :refresh, on: :collection
  end
  resources :x_sync_runs, only: [ :create, :update ]
  resources :x_billing_cycles, only: [ :create, :update ]
  resource :settings, only: [ :show, :update ]
  resources :imports, only: [ :create ]
  resources :archive_imports, only: [ :create ]
  resource :context_export, only: :show
  resource :mcp_token, only: [ :create, :destroy ]
  resources :grok_proposals, only: :update
  resources :grok_intakes, only: :create
  post "/mcp", to: "mcp#create", as: :mcp
  match "/mcp", to: "mcp#unsupported", via: [ :get, :delete ]
  resource :daily_session, only: :update
  post "/x/connection", to: "x_connections#create", as: :x_connection
  patch "/x/connection", to: "x_connections#update"
  delete "/x/connection", to: "x_connections#destroy"
  get "/x/connection/callback", to: "x_connections#callback", as: :x_connection_callback
  patch "/x/client_configuration", to: "x_client_configurations#update", as: :x_client_configuration
  get "/favicon.ico", to: redirect("/icon.svg")
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
