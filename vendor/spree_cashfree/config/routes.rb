Spree::Core::Engine.add_routes do
  post '/cashfree/create_session', to: 'cashfree#create_session'
  post '/cashfree/response', to: 'cashfree#cashfree_response', as: :cashfree_response
  get '/cashfree/response', to: 'cashfree#cashfree_response'
end