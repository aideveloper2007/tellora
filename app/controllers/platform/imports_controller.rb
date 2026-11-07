# frozen_string_literal: true

module Platform
  # "Move my store": the owner enters their current store's address, proves they
  # own the domain with a DNS TXT record, then creates their Tellora account.
  # The store build then reads their brand (see SiteImport).
  #
  # Kept in the session until the account is created:
  #   session[:store_import] = { 'url', 'domain', 'token', 'verified_at' }
  class ImportsController < BaseController
    VERIFIED_FOR = 24.hours

    before_action :load_import, only: %i[verify check]

    # GET /move
    def new
      @address = session.dig(:store_import, 'domain')
    end

    # POST /move
    def create
      url, domain = ImportOwnership.normalize(params[:address])
      previous = session[:store_import]
      token = previous.is_a?(Hash) && previous['domain'] == domain ? previous['token'] : SecureRandom.hex(12)
      session[:store_import] = { 'url' => url, 'domain' => domain, 'token' => token }
      redirect_to platform_import_verify_path
    rescue ImportOwnership::Invalid => e
      @address = params[:address].to_s.strip
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    # GET /move/verify
    def verify; end

    # POST /move/verify
    def check
      if ImportOwnership.verified?(@import['domain'], @import['token'])
        session[:store_import] = @import.merge('verified_at' => Time.current.iso8601)
        session[:store_prompt] = "Moving my store from #{@import['domain']}"
        redirect_to platform_signup_path
      else
        flash.now[:alert] = "We can't see the TXT record yet. DNS changes usually appear within a few minutes, " \
                            'but can take up to an hour. Check the name and value, then try again.'
        render :verify, status: :unprocessable_entity
      end
    end

    # A verified import in this session (used by StoreBuildsController), or nil
    def self.verified(session)
      import = session[:store_import]
      return nil unless import.is_a?(Hash) && import['verified_at'].present? && import['url'].present?

      verified_at = Time.zone.parse(import['verified_at'].to_s)
      verified_at && verified_at > VERIFIED_FOR.ago ? import : nil
    rescue ArgumentError
      nil
    end

    private

    def load_import
      @import = session[:store_import]
      redirect_to platform_import_path unless @import.is_a?(Hash) && @import['domain'].present? && @import['token'].present?
    end
  end
end
