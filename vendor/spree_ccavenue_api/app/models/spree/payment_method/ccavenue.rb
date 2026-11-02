module Spree
  class PaymentMethod::Ccavenue < Spree::PaymentMethod
    preference :merchant_id, :string
    preference :access_code, :string
    preference :encryption_key, :string
    preference :test_mode, :boolean, default: true
    
    def environment
      preferred_test_mode ? 'test' : 'production'
    end
    
    def environment=(env)
      self.preferred_test_mode = (env == 'test')
    end
    
    # Add the missing url method
    def url
      if preferred_test_mode
        'https://test.ccavenue.com/transaction/transaction.do'
      else
        'https://secure.ccavenue.com/transaction/transaction.do'
      end
    end
    
    def gateway_class
      nil
    end
    
    def payment_source_class
      nil
    end
    
    def source_required?
      false
    end
    
    def supports?(source)
      true
    end
    
    def method_type
      'ccavenue'
    end
    
    # Return failed response to force redirect to CCAvenue
    def purchase(money, source, gateway_options)
      ActiveMerchant::Billing::Response.new(false, "Redirect to CCAvenue required", {}, {})
    end
    
    def authorize(money, source, gateway_options)
      ActiveMerchant::Billing::Response.new(false, "Redirect to CCAvenue required", {}, {})
    end
    
    def capture(money, response_code, gateway_options)
      ActiveMerchant::Billing::Response.new(true, "Success", {}, {})
    end
    
    def void(response_code, gateway_options)
      ActiveMerchant::Billing::Response.new(true, "Success", {}, {})
    end
    
    # Don't auto-capture - require manual payment processing
    def auto_capture?
      false
    end
  end
end