require "uri"
require "json"
require "net/http"
require 'base64'

class CashfreeRefund
  def perform(credit_cents, cf_payment_id)
    url = URI("#{base_url}/pg/orders/#{order_id}/refunds")
    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE

    gateway = Spree::Gateway.find_by(type: "Spree::Gateway::CashfreeGateway")
    app_id = gateway.preferred_app_id
    secret_key = gateway.preferred_secret_key

    request = Net::HTTP::Post.new(url)
    request["Content-Type"] = "application/json"
    request["x-api-version"] = "2022-09-01"
    request["x-client-id"] = app_id
    request["x-client-secret"] = secret_key
    
    request.body = JSON.dump({
      "refund_amount": credit_cents / 100.0,
      "refund_id": "refund_#{Time.current.to_i}",
      "refund_note": "Refund from Spree"
    })

    response = https.request(request)
    response
  end

  private

  def base_url
    gateway = Spree::Gateway.find_by(type: "Spree::Gateway::CashfreeGateway")
    if gateway.preferred_environment == 'production'
      'https://api.cashfree.com'
    else
      'https://sandbox.cashfree.com'
    end
  end

  def order_id
    # This should be extracted from the payment source
    # For now, returning a placeholder
    "order_#{Time.current.to_i}"
  end
end