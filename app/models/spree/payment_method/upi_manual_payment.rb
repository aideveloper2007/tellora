module Spree
  class PaymentMethod::UpiManualPayment < PaymentMethod
    has_one_attached :qr_code
    preference :upi_id, :string
    #preference :qr_code, :file

    def payment_source_class
      nil
    end

    def source_required?
      false
    end

    def payment_icon_name
       self.class.name.demodulize.underscore
    end

    # Allow finding deleted payment methods
    def self.find_with_destroyed(id)
      unscope(where: :deleted_at).find(id)
    end

    def authorize(_amount, _source, _opts)
      ActiveMerchant::Billing::Response.new(true, "Payment will be verified manually")
    end

    def purchase(_amount, _source, _opts)
      ActiveMerchant::Billing::Response.new(true, "Payment will be verified manually")
    end

    def capture(amount, _source, _gateway_options)
      ActiveMerchant::Billing::Response.new(true, "Manual payment captured")
    end

    def void(_response_code, _source, _gateway_options = {})
      ActiveMerchant::Billing::Response.new(true, "Manual payment voided")
    end

    def credit(_amount, _response_code, _source, _gateway_options = {})
      ActiveMerchant::Billing::Response.new(true, "Manual payment credited")
    end


  end
end