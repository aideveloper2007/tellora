module Cashfree
  module CfOrder
    class Api < Cashfree::Base
      attr_reader :order

      def create(order_id)
        @order = Spree::Order.find_by(id: order_id)
        
        unless @order
          Rails.logger.error "Cashfree: Order not found with id #{order_id}"
          return order_id.to_s
        end
        
        uri = URI("#{base_url}/pg/orders")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 10
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['x-api-version'] = '2022-09-01'
        request['x-client-id'] = @app_id
        request['x-client-secret'] = @secret_key
        request.body = order_create_params.to_json

        Rails.logger.info "=== CASHFREE API REQUEST ==="
        Rails.logger.info "URL: #{uri}"
        Rails.logger.info "App ID: #{@app_id&.first(15)}..."
        Rails.logger.info "Body: #{order_create_params.to_json}"

        response = http.request(request)
        
        Rails.logger.info "=== CASHFREE API RESPONSE ==="
        Rails.logger.info "Code: #{response.code}"
        Rails.logger.info "Body: #{response.body}"
        
        if response.code == '200'
          result = JSON.parse(response.body)
          session_id = result['payment_session_id']
          
          if session_id.present?
            Rails.logger.info "SUCCESS: Session ID = #{session_id}"
            return session_id
          else
            Rails.logger.error "ERROR: No payment_session_id in response"
            return order.number
          end
        else
          Rails.logger.error "ERROR: API returned #{response.code}"
          return order.number
        end
        
      rescue StandardError => e
        Rails.logger.error "EXCEPTION: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        return order.number
      end

      private

 def order_create_params
  store = order.store
  host = store&.url || 'http://localhost:3000'
  host = "http://#{host}" unless host.start_with?('http')
  return_url = "#{host}/cashfree/response?order_id=#{order.number}"
  
  customer_id = (order.user_id || order.email).to_s.gsub(/[^a-zA-Z0-9_-]/, '_')
  
  # Make order ID unique by adding timestamp
  unique_order_id = "#{order.number}_#{Time.now.to_i}"
  
  {
    order_id: unique_order_id,
    order_amount: order.total.to_f,
    order_currency: order.currency,
    customer_details: {
      customer_id: customer_id,
      customer_email: order.email,
      customer_phone: order.bill_address&.phone || '9999999999',
      customer_name: order.bill_address&.full_name || order.email
    },
    order_meta: {
      return_url: return_url
    }
  }
end
    end
  end
end