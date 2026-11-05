# frozen_string_literal: true

module Internal
  # Private API for the certbot agent container (deploy/certbot_agent.py).
  # Only reachable inside the Docker network (http://app:3000/internal/tls/...)
  # and protected with the TLS_AGENT_TOKEN secret. Answers 404 when no token is set.
  class TlsController < ActionController::API
    before_action :authenticate!

    # GET /internal/tls/queue
    # issue:  domains whose DNS is correct and need a certificate
    # remove: domains the owner disconnected (delete certificate and nginx config)
    # active: domains with a certificate (for renewal)
    def queue
      render json: {
        issue: StoreDomain.where(status: 'issuing').order(:id).limit(20).map { |d| entry(d) },
        remove: StoreDomain.where(status: 'removing').order(:id).limit(20).map { |d| entry(d) },
        active: StoreDomain.where(status: 'active').order(:id).map { |d| entry(d) }
      }
    end

    # POST /internal/tls/issued { host: "mybrand.com" }
    def issued
      domain = find_domain or return
      domain.update_columns(status: 'active', ssl_issued_at: Time.current, error: nil, updated_at: Time.current)
      connect_spree_custom_domain(domain)
      StoreDomain.forget(domain.tenant_code)
      domain.hostnames.each { |h| TenantResolver.clear(h) }
      head :no_content
    end

    # POST /internal/tls/failed { host: "mybrand.com", error: "..." }
    def failed
      domain = find_domain or return
      domain.update_columns(status: 'failed', error: params[:error].to_s.truncate(500), updated_at: Time.current)
      head :no_content
    end

    # POST /internal/tls/removed { host: "mybrand.com" }
    def removed
      domain = StoreDomain.find_by(host: params[:host].to_s, status: 'removing')
      domain&.destroy
      head :no_content
    end

    private

    def entry(domain)
      { host: domain.host, names: domain.hostnames, primary: domain.primary_host, cert_name: domain.cert_name }
    end

    def find_domain
      domain = StoreDomain.find_by(host: params[:host].to_s)
      head(:not_found) unless domain
      domain
    end

    # Spree builds its links (menus, canonical tags, emails) from the store's default custom domain
    def connect_spree_custom_domain(domain)
      Apartment::Tenant.switch(domain.tenant_code) do
        store = Spree::Store.find_by(id: domain.store_id)
        next unless store

        record = Spree::CustomDomain.find_or_initialize_by(url: domain.primary_host)
        record.store = store
        record.default = true
        record.save!
        store.custom_domains.where.not(id: record.id).update_all(default: false)
        store.touch
      end
    rescue StandardError => e
      Rails.logger.error("[TLS] could not set Spree custom domain for #{domain.host}: #{e.class} - #{e.message}")
    end

    def authenticate!
      expected = ENV['TLS_AGENT_TOKEN'].to_s
      given = request.authorization.to_s.delete_prefix('Bearer ').strip
      return head(:not_found) if expected.empty?
      return if given.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

      head :unauthorized
    end
  end
end
