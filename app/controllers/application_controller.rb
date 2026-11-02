class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  
  #before_action :set_tenant_from_domain
  #prepend_before_action :set_tenant_from_domain
  before_action :set_current_store
  
  private
  
 
  
  def set_current_store
    Rails.logger.info "=== APPLICATION CONTROLLER: set_current_store called ==="
    Rails.logger.info "Current tenant: #{Apartment::Tenant.current}"
    Rails.logger.info "Request path: #{request.path}"
    
    if Apartment::Tenant.current != 'public'
      Apartment::Tenant.switch('public') do
        @current_store = Spree::Store.find_by(code: Apartment::Tenant.current)
      end
      
      Rails.logger.info "Found store: #{@current_store&.id}"
      
      if @current_store
        Spree::Store.current = @current_store
      else
        Rails.logger.warn "No store found for tenant: #{Apartment::Tenant.current}"
      end
    else
      Rails.logger.info "Tenant is public, checking if Spree::Store.current exists"
      Rails.logger.info "Spree::Store.current = #{Spree::Store.current.inspect rescue 'ERROR'}"
    end
    
    Rails.logger.debug "set_current_store completed successfully"
  rescue => e
    Rails.logger.error "ERROR in set_current_store: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end
  
def tenant_log(message)
  return if Apartment::Tenant.current == 'public'
  
  log_file = Rails.root.join('log', 'tenants', "#{Apartment::Tenant.current}.log")
  File.open(log_file, 'a') do |f|
    f.puts "[#{Time.current}] #{message}"
  end
end


  
  def current_store
    @current_store ||= Spree::Store.current
  end
  helper_method :current_store
end