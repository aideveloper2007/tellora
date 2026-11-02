Spree::Core::Engine.routes.draw do
  match '/gateway/:order_id/ccavenue/:payment_method_id' => 'ccavenue#show', :as => :gateway_ccavenue, via: [:get, :post]
  match '/gateway/ccavenue/:id/callback' => 'ccavenue#callback', :as => :gateway_ccavenue_callback, via: [:get, :post]

  namespace :admin do
    resources :payment_methods do
      member do
        get :verify
      end
    end
  end
end
