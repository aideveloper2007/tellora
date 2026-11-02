require 'razorpay'

module Spree
  class Gateway::RazorpayGateway < Gateway
    preference :key_id, :string
    preference :key_secret, :string
    preference :merchant_name, :string
    preference :merchant_description, :text
    preference :merchant_address, :string
    preference :theme_color, :string, default: '#F37254'

    def supports?(_source)
      true
    end

    def provider_class
      self
    end

    def provider
      Razorpay.setup(
        preferred_key_id,
        preferred_key_secret
      )
    end

    def credit(credit_cents, payment_id, originator)
      response = RazorpayRefund.new.perform(credit_cents, payment_id)
      ActiveMerchant::Billing::Response.new(
        response.code == "200",
        response, 
        error_code: response.code
      )
    end

    # Fixed cancel method to handle order cancellations
    def cancel(response_code, gateway_options = {})
      Rails.logger.info "=== CANCEL METHOD CALLED ==="
      Rails.logger.info "Response code: #{response_code}"
      Rails.logger.info "Gateway options: #{gateway_options.inspect}"
      
      # Extract payment information - try multiple approaches
      payment = gateway_options[:originator]
      
      if payment.nil?
        # If originator is nil, find the payment by response_code (which might be payment number)
        if response_code.present?
          payment = Spree::Payment.find_by(number: response_code) ||
                   Spree::Payment.find_by(id: response_code) ||
                   Spree::Payment.joins(:source).where(spree_payment_sources: { gateway_payment_profile_id: response_code }).first
          Rails.logger.info "Found payment by response_code: #{payment&.id}"
        end
      end
      
      if payment.nil? && gateway_options[:order_id]
        # Try to find payment by order
        order = Spree::Order.find(gateway_options[:order_id])
        payment = order.payments.where(state: 'completed', payment_method: self).last
        Rails.logger.info "Found payment by order: #{payment&.id}"
      end
      
      Rails.logger.info "Final payment found: #{payment&.id}"
      Rails.logger.info "Payment source: #{payment&.source&.inspect}"
      
      # Try multiple ways to get the Razorpay payment ID
      razorpay_payment_id = nil
      
      if payment&.source
        razorpay_payment_id = payment.source.gateway_payment_profile_id ||
                             payment.avs_response ||
                             payment.response_code
      end
      
      # Remove 'success' as it's not a valid payment ID
      razorpay_payment_id = nil if razorpay_payment_id == 'success'
      
      Rails.logger.info "Found Razorpay payment ID: #{razorpay_payment_id}"
      
      if razorpay_payment_id.present?
        # Convert amount to cents (Razorpay expects amount in smallest currency unit)
        amount_in_cents = (payment.amount * 100).to_i
        
        Rails.logger.info "Initiating Razorpay refund for payment: #{razorpay_payment_id}, amount: #{amount_in_cents}"
        
        # Use the existing refund service
        response = RazorpayRefund.new.perform(amount_in_cents, razorpay_payment_id)
        
        if response.code == "200"
          Rails.logger.info "✅ Razorpay refund successful"
          ActiveMerchant::Billing::Response.new(
            true,
            "Refund successful",
            JSON.parse(response.body)
          )
        else
          Rails.logger.error "❌ Razorpay refund failed: #{response.body}"
          ActiveMerchant::Billing::Response.new(
            false,
            "Refund failed: #{response.body}",
            {}
          )
        end
      else
        Rails.logger.error "❌ Cannot refund: No Razorpay payment ID found"
        # Return success anyway to allow order cancellation
        ActiveMerchant::Billing::Response.new(
          true,
          "Order canceled - manual refund required for Razorpay payment",
          {}
        )
      end
    rescue => e
      Rails.logger.error "❌ Razorpay refund error: #{e.message}"
      Rails.logger.error e.backtrace.first(5)
      # Return success to allow order cancellation even if refund fails
      ActiveMerchant::Billing::Response.new(
        true,
        "Order canceled - manual refund required: #{e.message}",
        {}
      )
    end

    # Add missing test? method
    def test?
      preferred_key_id.include?('test') || Rails.env.development?
    end

    def auto_capture?
      true
    end

    def method_type
      'razorpay'
    end

    def purchase(_amount, transaction_details, gateway_options = {})
      ActiveMerchant::Billing::Response.new(true, 'razorpay success')
    end

    def request_type
      'DEFAULT'
    end
  end
end