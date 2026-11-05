# frozen_string_literal: true

module Platform
  # Runs on the NEW STORE's own address: signs the owner in with the one-time link
  # from the store builder, then sends them to the builder (or the Domain screen).
  class HandoffController < ActionController::Base
    NEXT_PAGES = { 'domain' => '/tellora/domain' }.freeze

    # GET /tellora/welcome?token=...
    def show
      tenant = Apartment::Tenant.current
      build = StoreHandoff.redeem(params[:token], tenant)
      return redirect_to('/user/sign_in', alert: 'This link has expired. Please sign in with your email and password.') unless build

      user = Spree.user_class.find_by(id: build.admin_user_id)
      return redirect_to('/user/sign_in') unless user

      sign_in(Spree.user_class.model_name.singular_route_key.to_sym, user)
      redirect_to NEXT_PAGES.fetch(params[:next].to_s, '/tellora/builder')
    end
  end
end