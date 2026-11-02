module Spree
  module OrderMailerDecorator
    def default_url_options
      current_tenant = Apartment::Tenant.current
      
      if current_tenant != 'public'
        store = nil
        Apartment::Tenant.switch(current_tenant) do
          store = Spree::Store.first
        end
        
        if store
          host = store.url.gsub(/^https?:\/\//, '')
          { host: host, protocol: 'https' }
        else
          super
        end
      else
        super
      end
    end
  end
end

Spree::OrderMailer.prepend(Spree::OrderMailerDecorator)