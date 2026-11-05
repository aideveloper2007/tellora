# frozen_string_literal: true

module Platform
  # Account form -> background store build -> live progress -> open the new store.
  class StoreBuildsController < BaseController
    before_action :require_prompt, only: %i[new create]
    before_action :load_own_build, only: %i[show status try_again open]

    # GET /start
    def new
      @build = StoreBuild.new(currency: 'USD')
    end

    # POST /builds
    def create
      @build = StoreBuild.new(build_params.merge(prompt: session[:store_prompt], ip: request.remote_ip))
      @build.store_url = store_url_for(@build.subdomain.to_s.downcase.strip)

      if @build.save
        session[:store_build_token] = @build.token
        session.delete(:store_prompt)
        StoreBuildJob.perform_async(@build.id)
        redirect_to platform_store_build_path(@build.token)
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /builds/:token
    def show; end

    # GET /builds/:token/status  (polled by the progress page)
    def status
      render json: {
        status: @build.status,
        steps: @build.steps_for_display,
        error: @build.status == 'failed' ? @build.error : nil,
        store_url: @build.store_url,
        open_url: @build.status == 'done' ? platform_store_build_open_path(@build.token) : nil
      }
    end

    # POST /builds/:token/retry  ("Try again": continues from the step that failed)
    def try_again
      if @build.status == 'failed'
        @build.update!(status: 'queued', error: nil)
        StoreBuildJob.perform_async(@build.id)
      end
      redirect_to platform_store_build_path(@build.token)
    end

    # GET /builds/:token/open  -> one-time sign-in link into the new store
    # ?next=domain opens the Domain screen instead of the builder
    def open
      return redirect_to(platform_store_build_path(@build.token)) unless @build.status == 'done'

      token = StoreHandoff.issue(@build)
      next_part = params[:next] == 'domain' ? '&next=domain' : ''
      redirect_to "#{@build.store_url}/tellora/welcome?token=#{CGI.escape(token)}#{next_part}", allow_other_host: true
    end

    private

    def build_params
      params.require(:store_build).permit(:store_name, :subdomain, :email, :password, :currency)
    end

    def require_prompt
      redirect_to platform_landing_path(anchor: 'build') if session[:store_prompt].blank?
    end

    # Only the browser that started a build can see or open it
    def load_own_build
      @build = StoreBuild.find_by(token: params[:token])
      head :not_found unless @build && session[:store_build_token] == @build.token
    end

    # https://<subdomain>.<platform domain>[:port]  (port kept for local testing)
    def store_url_for(subdomain)
      domain = TenantResolver.platform_domains.first || request.host
      port = request.port
      port_part = [80, 443].include?(port) ? '' : ":#{port}"
      "#{request.protocol}#{subdomain}.#{domain}#{port_part}"
    end
  end
end