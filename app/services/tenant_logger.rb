# app/services/tenant_logger.rb
class TenantLogger
  def self.log(message, level: :info)
    return Rails.logger.public_send(level, message) if Apartment::Tenant.current == 'public'
    
    tenant_logger = get_tenant_logger(Apartment::Tenant.current)
    tenant_logger.public_send(level, "[#{Time.current}] #{message}")
  end

  private

  def self.get_tenant_logger(tenant_name)
    @loggers ||= {}
    @loggers[tenant_name] ||= begin
      log_dir = Rails.root.join('log', 'tenants')
      
      # Force create directory
      unless Dir.exist?(log_dir)
        Dir.mkdir(log_dir)
      end
      
      log_file = File.join(log_dir, "#{tenant_name}.log")
      Logger.new(log_file)
    end
  end
end