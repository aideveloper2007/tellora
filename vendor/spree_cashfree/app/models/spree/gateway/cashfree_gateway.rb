require 'net/http'
require 'json'

module Spree
  class Gateway::CashfreeGateway < Gateway
    preference :app_id, :string
    preference :secret_key, :string
    preference :merchant_name, :string
    preference :merchant_description, :text
    preference :theme_color, :string, default: '#2196F3'
    preference :environment, :string, default: 'sandbox'

    def supports?(_source)
      true
    end

    def provider_class
      self
    end

    def provider
      self
    end

    def payment_source_class
      Spree::CashfreeCheckout
    end

    def source_required?
      false
    end

    def base_url
      if preferred_environment == 'production'
        'https://api.cashfree.com'
      else
        'https://sandbox.cashfree.com'
      end
    end

    def authorize(money, source, gateway_options)
      ActiveMerchant::Billing::Response.new(true, 'Cashfree authorization pending', {}, {})
    end

    def credit(credit_cents, payment_id, originator)
      response = CashfreeRefund.new.perform(credit_cents, payment_id)
      ActiveMerchant::Billing::Response.new(
        response.code == "200",
        response.body,
        error_code: response.code
      )
    end

    def auto_capture?
      true
    end

    def method_type
      'cashfree'
    end

    def purchase(_amount, _transaction_details = {}, _gateway_options = {})
      ActiveMerchant::Billing::Response.new(true, 'cashfree success')
    end

    def request_type
      'DEFAULT'
    end
  end
end