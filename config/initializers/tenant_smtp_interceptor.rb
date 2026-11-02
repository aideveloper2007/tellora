# config/initializers/tenant_smtp_interceptor.rb

class TenantSmtpInterceptor
  def self.delivering_email(mail)
    current_tenant = Apartment::Tenant.current
    
    # Only override SMTP for specific tenants that need custom settings
    custom_smtp = case current_tenant
    when 'swawlamban'
      {
        address: 'smtp.gmail.com',
        port: 587,
        domain: 'swawlamban.in',
        user_name: 'swawlamban.in@gmail.com',
        password: 'ztrtpvyktewvqlrz', # Replace with real password
        authentication: :plain,
        enable_starttls_auto: true
      }
    # Add more tenants with custom SMTP as needed
    # when 'hilaptop'
    #   {
    #     address: 'smtp.gmail.com',
    #     port: 587,
    #     domain: 'hilaptop.com',
    #     user_name: 'sales@hilaptop.com',
    #     password: 'password-here',
    #     authentication: :plain,
    #     enable_starttls_auto: true
    #   }
    else
      nil # Use default AWS SES SMTP from smtp_settings.rb
    end
    
    # Apply custom SMTP if defined for this tenant
    if custom_smtp
      mail.delivery_method.settings.merge!(custom_smtp)
    end
  end
end

ActionMailer::Base.register_interceptor(TenantSmtpInterceptor)