# frozen_string_literal: true

module Platform
  # "Move my store": the owner enters their current store's address and goes
  # straight to the account form. The build then reads their brand (SiteImport)
  # and their new store opens on its Tellora subdomain. They connect their own
  # domain later, from the Domain screen, once they are happy with it.
  #
  # Kept in the session until the account is created:
  #   session[:store_import] = { 'url', 'domain' }
  class ImportsController < BaseController
    # GET /move
    def new
      @address = session.dig(:store_import, 'domain')
    end

    # POST /move
    def create
      url, domain = ImportAddress.normalize(params[:address])
      session[:store_import] = { 'url' => url, 'domain' => domain }
      session[:store_prompt] = "Moving my store from #{domain}"
      redirect_to platform_signup_path
    rescue ImportAddress::Invalid => e
      @address = params[:address].to_s.strip
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    # The store being moved in this session (used by StoreBuildsController), or nil
    def self.pending(session)
      import = session[:store_import]
      import.is_a?(Hash) && import['url'].present? ? import : nil
    end
  end
end