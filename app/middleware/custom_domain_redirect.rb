# frozen_string_literal: true

# When a store has a connected custom domain, visitors who open its Tellora address
# (mybrand.tellora.store) are sent to the custom domain (www.mybrand.com) with a
# permanent redirect, so search engines and customers use one address.
#
# The builder, admin, login and other setup paths stay on the Tellora address.
# Runs after CustomDomainTenantElevator, so the store's tenant is already known.
class CustomDomainRedirect
  STAY_PATHS = (StorePublishGate::ALWAYS_OPEN + %w[/internal /.well-known]).freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    target = redirect_target(env)
    return [301, { 'location' => target, 'cache-control' => 'public, max-age=300' }, []] if target

    @app.call(env)
  end

  private

  def redirect_target(env)
    method = env['REQUEST_METHOD']
    return unless method == 'GET' || method == 'HEAD'

    tenant = env['apartment.tenant']
    return if tenant.blank? || tenant == TenantResolver::PUBLIC

    path = env['PATH_INFO'].to_s
    return if STAY_PATHS.any? { |prefix| path.start_with?(prefix) }

    request = ActionDispatch::Request.new(env)
    host = TenantResolver.normalize(request.host)
    return unless TenantResolver.platform_subdomain(host) # only the *.tellora.store address

    primary = StoreDomain.primary_host_for(tenant)
    return unless primary && primary != host

    "https://#{primary}#{request.fullpath}"
  rescue StandardError => e
    Rails.logger.error("[CustomDomainRedirect] #{e.class} - #{e.message}")
    nil
  end
end
