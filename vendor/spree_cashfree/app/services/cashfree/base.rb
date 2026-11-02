module Cashfree
  class Base
    def initialize
      setup_cashfree
    end

    private

    def find_payment_gateway
      Spree::PaymentMethod.find_by(type: 'Spree::Gateway::CashfreeGateway')
    end

    def setup_cashfree
      gateway = find_payment_gateway
      @app_id = gateway.preferred_app_id
      @secret_key = gateway.preferred_secret_key
      @environment = gateway.preferred_environment
    end

    def base_url
      if @environment == 'production'
        'https://api.cashfree.com'
      else
        'https://sandbox.cashfree.com'
      end
    end
  end
end