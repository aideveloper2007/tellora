# frozen_string_literal: true

# Single source of truth for "which store (Apartment schema) does this host belong to?"
#
# Used by CustomDomainTenantElevator (every request) and the ActiveStorage hook.
#
#   localhost / <platform domain> / www.<platform domain> -> 'public' (platform / landing page)
#   shop.<platform domain>                                -> schema of the store whose subdomain is 'shop'
#   www.customshop.com / customshop.com                   -> schema of the store that connected that domain
#                                                            (StoreDomain, or a store whose url is exactly that domain)
#   anything unknown                                      -> 'public'
#
# Platform domains come ONLY from ENV TENANT_DOMAINS (comma separated), e.g. "mydomain.com".
# Default when unset: "lvh.me" (always resolves to 127.0.0.1, for local multi-store testing).
#
# Found hosts are cached for 5 minutes. Unknown hosts are never cached, so a brand-new store
# works on its very first request. Call TenantResolver.clear(host) after changing a store's
# subdomain or url to apply it immediately.
class TenantResolver
  PUBLIC = 'public'
  CACHE_TTL = 5 * 60 # seconds
  CACHE_PREFIX = 'tenant_resolver:v1:'

  LOCAL_HOSTS = %w[localhost 127.0.0.1 0.0.0.0].freeze

  # Subdomains of the platform domain that never belong to a store
  RESERVED_SUBDOMAINS = %w[www admin api mail ftp assets cdn blog help support docs app staging test demo].freeze

  # Store codes whose schema has a different name
  LEGACY_CODES = {
    'creativecraftindia-1098' => 'creativecraftindia'
  }.freeze

  class << self
    # Returns the schema name to switch to. Never raises.
    def resolve(host)
      host = normalize(host)
      return PUBLIC if host.empty? || platform_host?(host)

      cached = cache_read(host)
      return cached if cached

      tenant = lookup(host)
      cache_write(host, tenant) unless tenant == PUBLIC
      tenant
    rescue StandardError => e
      log_error("resolve(#{host.inspect}) failed: #{e.class} - #{e.message}")
      PUBLIC
    end

    # Forget a cached host (call after changing a store's subdomain or url)
    def clear(host)
      Rails.cache.delete(cache_key(normalize(host)))
    end

    def platform_domains
      ENV.fetch('TENANT_DOMAINS', 'lvh.me')
         .split(',')
         .map { |d| d.strip.downcase }
         .reject(&:empty?)
    end

    def platform_host?(host)
      return true if LOCAL_HOSTS.include?(host)

      platform_domains.any? { |domain| host == domain || host == "www.#{domain}" }
    end

    # "shop.<platform domain>" -> "shop"; nil for anything that isn't a single-level store subdomain
    def platform_subdomain(host)
      platform_domains.each do |domain|
        suffix = ".#{domain}"
        next unless host.end_with?(suffix)

        sub = host[0...-suffix.length]
        return nil if sub.empty? || sub.include?('.') || RESERVED_SUBDOMAINS.include?(sub)

        return sub
      end
      nil
    end

    # Every exact way a store url can be written for this host (with/without www, http/https, trailing slash)
    def url_variants(host)
      bare = host.start_with?('www.') ? host.sub('www.', '') : host
      [bare, "www.#{bare}"].flat_map do |h|
        %w[https http].flat_map { |scheme| ["#{scheme}://#{h}", "#{scheme}://#{h}/"] }
      end
    end

    def normalize(host)
      host.to_s.strip.downcase.chomp('.')
    end

    private

    # A subdomain resolves to the store with that subdomain, else a schema with that exact name.
    def lookup(host)
      candidates =
        if (sub = platform_subdomain(host))
          [code_for_subdomain(sub), sub]
        else
          [code_for_custom_domain(host)]
        end

      candidates.compact
                .map { |code| LEGACY_CODES.fetch(code, code) }
                .uniq
                .find { |schema| schema != PUBLIC && schema_exists?(schema) } || PUBLIC
    end

    # Spree::Store is an Apartment excluded model, so these queries always hit the public schema.
    def code_for_subdomain(sub)
      if store_has_subdomain_column?
        code = Spree::Store.where(subdomain: sub).where.not(code: [nil, '']).order(:id).pick(:code)
        return code if code
      end
      Spree::Store.where(code: sub).pick(:code)
    end

    # Connected custom domains first (StoreDomain, public schema), then a store whose url is that domain
    def code_for_custom_domain(host)
      tenant = StoreDomain.tenant_for_host(host) if defined?(StoreDomain) && StoreDomain.table_exists?
      return tenant if tenant

      Spree::Store.where(url: url_variants(host)).where.not(code: [nil, '']).order(:id).pick(:code)
    end

    def store_has_subdomain_column?
      @store_has_subdomain_column = Spree::Store.column_names.include?('subdomain') if @store_has_subdomain_column.nil?
      @store_has_subdomain_column
    end

    def schema_exists?(name)
      connection = ActiveRecord::Base.connection
      connection.select_value("SELECT 1 FROM pg_namespace WHERE nspname = #{connection.quote(name)}").present?
    end

    def cache_key(host)
      "#{CACHE_PREFIX}#{host}"
    end

    def cache_read(host)
      Rails.cache.read(cache_key(host))
    rescue StandardError
      nil # a cache outage must never take stores down
    end

    def cache_write(host, tenant)
      Rails.cache.write(cache_key(host), tenant, expires_in: CACHE_TTL)
    rescue StandardError
      nil
    end

    def log_error(message)
      Rails.logger.error("[TenantResolver] #{message}")
    end
  end
end