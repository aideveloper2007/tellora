# frozen_string_literal: true

# Single Apartment configuration (previously split between application.rb and this file).
Apartment.configure do |config|
  # Shared across all tenants, always in the public schema:
  #   Spree::Store - store records (TenantResolver looks stores up there)
  #   StoreBuild   - "Build my store" requests from the platform landing page
  config.excluded_models = %w[Spree::Store StoreBuild]

  # All store schemas, used by Apartment for tenant migrations
  config.tenant_names = lambda do
    begin
      schemas = ActiveRecord::Base.connection.execute(
        "SELECT schema_name FROM information_schema.schemata
         WHERE schema_name NOT IN ('information_schema', 'pg_catalog', 'pg_toast_temp_1', 'pg_toast', 'public')
           AND schema_name NOT LIKE 'pg_%'"
      ).values.flatten

      ['public'] + schemas
    rescue StandardError
      ['public']
    end
  end

  config.default_tenant = 'public'
end

# Tenant switching is done by CustomDomainTenantElevator (config/application.rb),
# using TenantResolver. Do not add Apartment's Subdomain elevator.