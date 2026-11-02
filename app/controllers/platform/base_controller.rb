# frozen_string_literal: true

module Platform
  # Shared base for the platform's own pages (landing page, store builder).
  # Inherits ActionController::Base on purpose: no Spree store context is needed here.
  class BaseController < ActionController::Base
    layout 'platform'
    protect_from_forgery with: :exception

    helper_method :platform_name

    private

    # Set PLATFORM_NAME in the environment to change the brand name
    def platform_name
      ENV.fetch('PLATFORM_NAME', 'Tellora')
    end
  end
end
