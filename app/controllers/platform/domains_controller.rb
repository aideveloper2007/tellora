# frozen_string_literal: true

module Platform
  # The owner's "Domain" screen (/tellora/domain), on the store's own address.
  # Connect a domain the owner already owns: we show the DNS records to add,
  # check them, get a free SSL certificate and switch the store to that domain.
  #
  # Uses the builder's owner check (load_build, require_owner).
  class DomainsController < BuilderController
    before_action :load_domain

    # GET /tellora/domain
    def show
      @store_host = DomainVerifier.store_host(@domain || StoreDomain.new(store_id: @build.store_id, tenant_code: @build.tenant_code))
      @server_ip = DomainVerifier.server_ip
      @records = @domain&.dns_records(store_host: @store_host, server_ip: @server_ip.presence || 'your server IP')

      respond_to do |format|
        format.html
        format.json { render json: status_json }
      end
    end

    # POST /tellora/domain  { domain: "mybrand.com", primary: "www" | "apex" }
    def create
      return redirect_to(platform_domain_path) if @domain

      input = StoreDomain.normalize(params[:domain])
      base = input.delete_prefix('www.')
      domain = StoreDomain.new(
        store_id: @build.store_id,
        tenant_code: @build.tenant_code,
        host: input,
        primary_host: params[:primary] == 'apex' ? base : nil
      )

      if domain.save
        DomainCheckJob.perform_in(60, domain.id)
        redirect_to platform_domain_path, notice: 'Now add the DNS records below at your domain provider.'
      else
        redirect_to platform_domain_path(domain: params[:domain]), alert: domain.errors.full_messages.to_sentence
      end
    end

    # POST /tellora/domain/check  ("Check now")
    def check
      return redirect_to(platform_domain_path) unless @domain

      if @domain.pending? || @domain.failed?
        report = DomainVerifier.new(@domain).call
        DomainCheckJob.perform_in(DomainCheckJob::RECHECK_EVERY, @domain.id) unless report['ok']
        flash[report['ok'] ? :notice : :info] = report['message']
      end
      redirect_to platform_domain_path
    end

    # DELETE /tellora/domain
    def destroy
      return redirect_to(platform_domain_path) unless @domain

      remove_spree_custom_domain(@domain)
      if @domain.active? || @domain.issuing? || @domain.failed?
        @domain.update_columns(status: 'removing', updated_at: Time.current) # the certbot agent cleans up, then deletes it
      else
        @domain.destroy
      end
      StoreDomain.forget(@build.tenant_code)
      @domain.hostnames.each { |h| TenantResolver.clear(h) }

      redirect_to platform_domain_path, notice: "#{@domain.host} was disconnected from your store."
    end

    private

    def load_domain
      @domain = StoreDomain.where(tenant_code: @build.tenant_code).where.not(status: 'removing').order(:id).last
    end

    def status_json
      return { status: 'none' } unless @domain

      {
        status: @domain.status,
        host: @domain.host,
        primary_host: @domain.primary_host,
        last_checked_at: @domain.last_checked_at&.iso8601,
        report: @domain.dns_report
      }
    end

    def remove_spree_custom_domain(domain)
      Spree::CustomDomain.where(url: domain.hostnames).destroy_all
    rescue StandardError => e
      Rails.logger.warn("[Domains] could not remove Spree custom domain: #{e.message}")
    end
  end
end
