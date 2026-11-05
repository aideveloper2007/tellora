 # config/routes.rb
require 'sidekiq/web'
Rails.application.routes.draw do
  # Platform landing page: only on the main domain (and localhost), never on store subdomains.
  # Must stay ABOVE the Spree mount so it wins for "/" on those hosts.
  constraints(->(request) { TenantResolver.platform_host?(TenantResolver.normalize(request.host)) }) do
    get  '/',                     to: 'platform/landing#show',            as: :platform_landing
    post '/start',                to: 'platform/landing#start',           as: :platform_start
    get  '/start',                to: 'platform/store_builds#new',        as: :platform_signup
    post '/builds',               to: 'platform/store_builds#create',     as: :platform_store_builds
    get  '/builds/:token',        to: 'platform/store_builds#show',       as: :platform_store_build
    get  '/builds/:token/status', to: 'platform/store_builds#status',     as: :platform_store_build_status
    post '/builds/:token/retry',  to: 'platform/store_builds#try_again',  as: :platform_store_build_retry
    get  '/builds/:token/open',   to: 'platform/store_builds#open',       as: :platform_store_build_open
  end

  # On each STORE's own address (never the platform domain):
  #   one-time sign-in link from the store builder, then the owner's builder screen
  get  '/tellora/welcome',                  to: 'platform/handoff#show',          as: :platform_handoff
  get  '/tellora/builder',                  to: 'platform/builder#show',          as: :platform_builder
  post '/tellora/builder/refine',           to: 'platform/builder#refine',        as: :platform_builder_refine
  get  '/tellora/builder/refine/:theme_id', to: 'platform/builder#refine_status', as: :platform_builder_refine_status
  post '/tellora/builder/publish',          to: 'platform/builder#publish',       as: :platform_builder_publish
  post '/tellora/builder/style',            to: 'platform/builder#style',         as: :platform_builder_style

  # Custom domain screen (store owner), on the store's own address
  get    '/tellora/domain',                 to: 'platform/domains#show',          as: :platform_domain
  post   '/tellora/domain',                 to: 'platform/domains#create'
  post   '/tellora/domain/check',           to: 'platform/domains#check',         as: :platform_domain_check
  delete '/tellora/domain',                 to: 'platform/domains#destroy'

  # Private API for the certbot agent container (SSL for custom domains), token protected
  get  '/internal/tls/queue',               to: 'internal/tls#queue'
  post '/internal/tls/issued',              to: 'internal/tls#issued'
  post '/internal/tls/failed',              to: 'internal/tls#failed'
  post '/internal/tls/removed',             to: 'internal/tls#removed'

  # Handle old URL redirects ONLY for magnafieldndt.com
  get '/t/products/*path', to: redirect { |params, request|
   path = params[:path]
    # Categories that should go to accessories
   accessories_categories = ['ultrasonic-testing-accessories', 'dye-penetrant-testing', 'sr-slash-pwht-equipments']
    # Get the main category (first part of path)
    main_category = path.split('/').first
    # Redirect to appropriate section
    if accessories_categories.include?(main_category)
      "/t/categories/accessories/#{path}"
    else
      "/t/categories/products/#{path}"
    end
  }, constraints: ->(request) { request.host.include?('magnafieldndt.com') }
  # Handle old blog URL redirects ONLY for magnafieldndt.com
 # get '/pages/blog', to: redirect('/posts'), constraints: ->(request) { request.host.include?('magnafieldndt.com') }
 # get '/pages/*slug', to: redirect { |params, request|
 #   "/posts/#{params[:slug]}"
 # }, constraints: ->(request) { request.host.include?('magnafieldndt.com') }
  # Custom routes for your app
  resources :tenant_registrations, only: [:new, :create]
  
  # Theme Designer / Chatbot routes
  resources :theme_designer, only: [:index] do
    collection do
      post :chat
      post :upload_prd
      post :generate_theme
      get :preview_theme, path: 'preview/:theme_id', as: :preview
      post :publish_theme
      get :history
    end
  end
  
  # GenAI Theme Chatbot routes (NEW)
  resources :genai_themes, only: [:index] do
    collection do
      get :chat
      post :send_message
      post :upload_prd
      post :generate
    end
    
    member do
      get :status
      get :preview
      get :test_simple
      post :refine
      post :apply
      post :activate  # NEW: Activate theme (set as default)
      post :deactivate  # NEW: Deactivate theme (return to default)
    end
  end
  
  # LMS APIs (NEW - Simple user and store creation)
  namespace :api do
    namespace :v1 do
      post 'users', to: 'users#create'      # Create main app user
      post 'stores', to: 'stores#create'    # Create store for existing user
      # Tenant-specific user management (EXISTING)
      resources :tenants, param: :tenant_code, only: [] do
        resources :users, only: [:create, :show, :index]
        get :status, to: 'users#tenant_status'
      end
    end
  end
  # Add custom Spree routes
  Spree::Core::Engine.add_routes do
    scope '(:locale)', locale: /#{Spree.available_locales.join('|')}/, defaults: { locale: nil } do
      devise_for(
        Spree.user_class.model_name.singular_route_key,
        class_name: Spree.user_class.to_s,
        path: :user,
        controllers: {
          sessions: 'spree/user_sessions',
          passwords: 'spree/user_passwords',
          registrations: 'spree/user_registrations'
        },
        router_name: :spree
      )
    end
    # Add import routes
    namespace :admin do
      resources :import_logs, only: [:index, :show] do
        get :import_sample, on: :collection
      end
      resources :products do
        get :import, on: :collection
        post :import, on: :collection
      end
      resource :shiprocket_settings, only: [:edit, :update]
      resources :orders do
        member do
          get :invoice
          get :packaging_slip
        end
      end
    end
  end
  #post '/checkout/:token/razorpay_success', to: 'checkout#razorpay_success'
  #post '/checkout/:token/razorpay_failure', to: 'checkout#razorpay_failure'
  post '/razorpay/payment/success', to: 'razorpay_payment#success', as: :razorpay_payment_success
  mount Spree::Core::Engine, at: '/'
  mount Sidekiq::Web => "/sidekiq" # access it at http://localhost:3000/sidekiq
  get "up" => "rails/health#show", as: :rails_health_check
  root "spree/home#index"
end