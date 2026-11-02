# frozen_string_literal: true

# Switches to the right store (Apartment schema) for every request, based on the host.
# All the lookup rules live in TenantResolver (app/services/tenant_resolver.rb).
#
# The tenant is reset to 'public' after each request, so one request can never leak
# its store into the next request handled by the same server thread.
class CustomDomainTenantElevator
  def initialize(app)
    @app = app
  end

  def call(env)
    host = ActionDispatch::Request.new(env).host
    tenant = TenantResolver.resolve(host)

    begin
      Apartment::Tenant.switch!(tenant)
    rescue Apartment::TenantNotFound
      tenant = TenantResolver::PUBLIC
      Apartment::Tenant.switch!(tenant)
    end

    env['apartment.tenant'] = tenant

    begin
      @app.call(env)
    ensure
      Apartment::Tenant.reset
    end
  end
end