module Spree
  class CashfreeController < StoreController
    skip_before_action :verify_authenticity_token
    include Spree::CashFree

    def create_session
      begin
        order = Spree::Order.find(params[:order_id])
        
        Rails.logger.info "Creating Cashfree session for order: #{order.id}"
        
        api = Cashfree::CfOrder::Api.new
        session_id = api.create(order.id)
        
        Rails.logger.info "Cashfree session created: #{session_id}"
        
        render json: { 
          session_id: session_id,
          order_number: order.number
        }
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "Order not found: #{params[:order_id]}"
        render json: { error: "Order not found: #{e.message}" }, status: 404
      rescue => e
        Rails.logger.error "Cashfree session error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        render json: { 
          error: e.message,
          error_class: e.class.to_s 
        }, status: 500
      end
    end

def cashfree_response
  order = load_order
  
  unless order
    flash[:error] = 'Order not found'
    redirect_to root_path and return
  end

  Rails.logger.info "Cashfree callback for order: #{order.number}, state: #{order.state}"

  begin
    if order.completed?
      flash[:notice] = 'This order has already been completed'
      redirect_to order_path(order, token: order.token)
      return
    end

    existing_payment = order.payments.find_by(payment_method: payment_method, state: 'completed')
    
    unless existing_payment
      payment = order.payments.create!(
        payment_method: payment_method,
        amount: order.total,
        state: 'completed',
        response_code: 'success'
      )
      Rails.logger.info "Payment created: #{payment.id}"
    end
    
    until order.completed?
      order.next!
    end
    
    Rails.logger.info "Order completed: #{order.number}"
    
    flash[:success] = 'Payment completed successfully!'
    redirect_to order_path(order, token: order.token)
    
  rescue => e
    Rails.logger.error "Error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    
    flash[:error] = "Payment error: #{e.message}"
    redirect_to root_path
  end
end

    private

    def verify_signature
      return true # Implement proper signature verification later
      post_data = "#{params['orderId']}|#{params['orderAmount']}|#{params['referenceId']}|#{params['txStatus']}|#{params['paymentMode']}|#{params['txMsg']}|#{params['txTime']}"
      expected_signature = OpenSSL::HMAC.hexdigest('SHA256', payment_method.preferred_secret_key, post_data)
      params['signature'] == expected_signature
    end

    def payment_method
      Spree::PaymentMethod.find(params[:payment_method_id])
    end

    def load_order
      order_number = params[:orderId] || params[:order_id]
      Spree::Order.find_by(number: order_number)
    end

    def completion_route
      order_path(load_order)
    end
  end
end