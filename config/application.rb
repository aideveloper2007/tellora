require_relative "boot"
require "rails/all"
require_relative '../app/middleware/custom_domain_tenant_elevator'
require_relative '../app/middleware/store_publish_gate'
require_relative '../app/middleware/custom_domain_redirect'

Bundler.require(*Rails.groups)

module SpreeStarter
  class Application < Rails::Application
    config.to_prepare do
      # Load application's model / class decorators
      Dir.glob(File.join(File.dirname(__FILE__), "../app/**/*_decorator*.rb")) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
      
      [ActiveStorage::BaseController, ActiveStorage::Representations::ProxyController].each do |controller_class|
        controller_class.class_eval do
          prepend_before_action :set_tenant_for_activestorage
          
          private
          
          # Images/files must load from the same store as the page.
          # The middleware has already chosen the tenant; reuse it (same rules via TenantResolver).
          def set_tenant_for_activestorage
            tenant = request.env['apartment.tenant'] || TenantResolver.resolve(request.host)
            Apartment::Tenant.switch!(tenant)
          end
        end
      end
    end
    
    config.after_initialize do
      # Create tenant logs directory
      tenant_log_dir = Rails.root.join('log', 'tenants')
      Dir.mkdir(tenant_log_dir) unless Dir.exist?(tenant_log_dir)
      
      # Override Rails logger to automatically separate tenant logs
      original_logger = Rails.logger
      
      Rails.logger = Logger.new(STDOUT).tap do |logger|
        logger.formatter = original_logger.formatter
        logger.level = original_logger.level
        
        # Override the add method to write tenant-specific logs
        def logger.add(severity, message = nil, progname = nil)
          super # Keep console output
          
          # Write to tenant-specific log file
          tenant = Apartment::Tenant.current rescue 'public'
          if tenant != 'public'
            log_file = Rails.root.join('log', 'tenants', "#{tenant}.log")
            formatted_message = message || (block_given? ? yield : progname)
            File.open(log_file, 'a') do |f|
              f.puts "[#{Time.current}] [#{%w[DEBUG INFO WARN ERROR FATAL UNKNOWN][severity] || 'ANY'}] #{formatted_message}"
            end
          end
        end
      end
      

    end

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    config.autoload_lib(ignore: %w[assets tasks])
    
    # Tenant switching: ONE middleware for every host (subdomains + custom domains).
    # Rules live in app/services/tenant_resolver.rb.
    # (Apartment's Subdomain elevator was removed: it overrode this one and broke stores
    #  whose subdomain differs from their schema name.)
    config.middleware.use CustomDomainTenantElevator

    # New stores stay private ("Opening soon") until the owner presses Publish in the builder
    config.middleware.insert_after CustomDomainTenantElevator, StorePublishGate

    # Stores with a connected custom domain: send visitors from the Tellora address to it
    config.middleware.insert_after StorePublishGate, CustomDomainRedirect
    
    if Rails.env.development?
      config.active_storage.resolve_model_to_route = :rails_storage_proxy
    end  
    
    config.active_record.yaml_column_permitted_classes = [
      Symbol, 
      BigDecimal, 
      Date, 
      Time, 
      ActiveSupport::TimeWithZone, 
      ActiveSupport::TimeZone, 
      ActiveSupport::HashWithIndifferentAccess
    ]
  end
end

# Apartment configuration lives in config/initializers/apartment.rb