class RazorpayPaymentController < ApplicationController
  protect_from_forgery except: [:success]

  def success
    begin
      @order = Spree::Order.find_by!(token: params[:order_token])
      
      Rails.logger.info "Processing Razorpay payment for order: #{@order.number}"
      
      unless params[:razorpay_payment_id].present?
        redirect_to "/checkout/#{@order.token}/payment", alert: "Payment verification failed"
        return
      end

      payment_method = Spree::PaymentMethod.find_by(type: 'Spree::Gateway::RazorpayGateway')

      # CAPTURE THE PAYMENT ON RAZORPAY'S SIDE FIRST
      begin
        require 'razorpay'
        Razorpay.setup(payment_method.preferences[:key_id], payment_method.preferences[:key_secret])
        razorpay_payment = Razorpay::Payment.fetch(params[:razorpay_payment_id])
        capture_result = razorpay_payment.capture(amount: (@order.total * 100).to_i)
        Rails.logger.info "✅ Payment captured on Razorpay: #{params[:razorpay_payment_id]}"
      rescue => e
        Rails.logger.error "❌ Payment capture failed: #{e.message}"
        redirect_to "/checkout/#{@order.token}/payment", alert: "Payment capture failed. Please try again."
        return
      end

      source = Spree::PaymentSource.create!(
        gateway_payment_profile_id: params[:razorpay_payment_id]
      )

      payment = @order.payments.create!(
        payment_method: payment_method,
        amount: @order.total,
        state: 'completed',
        source: source,
        response_code: 'success',
        avs_response: params[:razorpay_payment_id]
      )

      @order.update!(
        payment_state: 'paid',
        payment_total: @order.total
      )

      while @order.next
        @order.save!
      end

      # Fix missing bill address if needed
      if @order.bill_address_id.nil? && @order.ship_address_id.present?
        @order.update!(bill_address_id: @order.ship_address_id)
      end

      # Send emails immediately
      begin
        Spree::OrderMailer.confirm_email(@order.id).deliver_now
        Spree::OrderMailer.store_owner_notification_email(@order.id).deliver_now
        @order.update!(confirmation_delivered: true)
        Rails.logger.info "✅ Emails sent for order: #{@order.number}"
      rescue => e
        Rails.logger.error "Email sending failed: #{e.message}"
      end

      Rails.logger.info "Order completed: #{@order.number}"
      redirect_to "/orders/#{@order.number}", notice: "Payment successful! Your order has been confirmed."

    rescue => e
      Rails.logger.error "Payment error: #{e.message}"
      redirect_to "/", alert: "Payment processing failed."
    end
  end
end