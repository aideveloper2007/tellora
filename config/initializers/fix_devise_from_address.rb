Rails.application.config.to_prepare do
  Devise::Mailer.class_eval do
    def initialize(*args)
      super(*args)
      
      # Set store email as from address for current tenant
      if defined?(Apartment::Tenant) && Apartment::Tenant.current != 'public'
        begin
          store = Spree::Store.first
          if store&.mail_from_address.present?
            self.class.default from: store.mail_from_address
          end
        rescue => e
          Rails.logger.error "Failed to set store from address: #{e.message}"
        end
      end
    end
  end
end