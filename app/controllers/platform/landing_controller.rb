# frozen_string_literal: true

module Platform
  # Public landing page of the platform (main domain / localhost only).
  # Stores keep their own storefronts on their own subdomains.
  class LandingController < BaseController
    PROMPT_MIN = 3
    PROMPT_MAX = 500

    # GET /
    def show
      @prompt = session[:store_prompt]
    end

    # POST /start  (the "Build my store" form)
    def start
      prompt = params[:prompt].to_s.strip

      if prompt.length < PROMPT_MIN
        flash[:alert] = 'Describe what your business sells, in a few words.'
        return redirect_to platform_landing_path(anchor: 'build')
      end

      session[:store_prompt] = prompt[0, PROMPT_MAX]
      redirect_to platform_signup_path
    end
  end
end