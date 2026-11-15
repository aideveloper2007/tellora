# frozen_string_literal: true

module Shiprocket
  # The Shiprocket API (https://apiv2.shiprocket.in/v1/external), for one store's account.
  #
  # Logs in with the store's API user, keeps the token on the account and renews it
  # before it expires. If Shiprocket says the token is no longer valid, it logs in
  # again once and repeats the request.
  #
  #   client = account.client
  #   client.rates(pickup_postcode:, delivery_postcode:, weight:, cod:)
  #   client.pickup_locations
  #   client.create_order(payload)            -> { "order_id", "shipment_id", ... }
  #   client.assign_awb(shipment_id, courier_id)
  #   client.schedule_pickup(shipment_id)
  #   client.label(shipment_id)               -> label PDF URL
  #   client.track(awb)
  #   client.cancel(sr_order_id)
  class Client
    BASE_URL = 'https://apiv2.shiprocket.in/v1/external'
    TOKEN_LIFETIME = 8 * 24 * 60 * 60 # seconds; renewed early (Shiprocket tokens last up to 10 days)
    TIMEOUT = 20 # seconds
    RATE_TIMEOUT = 8 # seconds, at checkout

    class Error < StandardError; end
    class AuthError < Error; end

    def initialize(account)
      @account = account
    end

    # Checks the email and password. Returns the token or raises AuthError.
    def login!
      response = HTTParty.post("#{BASE_URL}/auth/login",
                               body: { email: @account.email, password: @account.password }.to_json,
                               headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
                               timeout: TIMEOUT)
      token = response.parsed_response.is_a?(Hash) ? response.parsed_response['token'] : nil
      unless response.success? && token.present?
        raise AuthError, 'Shiprocket did not accept this API user email and password. ' \
                         'Check them in Shiprocket: Settings > API > Configure.'
      end

      if @account.persisted?
        @account.update_columns(token: token, token_expires_at: TOKEN_LIFETIME.seconds.from_now, updated_at: Time.current)
      else
        @account.token = token
        @account.token_expires_at = TOKEN_LIFETIME.seconds.from_now
      end
      token
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
      raise Error, 'Shiprocket did not respond. Please try again in a minute.'
    end

    # Couriers that deliver from the pickup pincode to the customer's pincode.
    # Returns { couriers: [{ id:, name:, rate:, days:, etd: }], recommended_id: }
    def rates(pickup_postcode:, delivery_postcode:, weight:, cod: false, declared_value: nil, timeout: RATE_TIMEOUT)
      query = { pickup_postcode: pickup_postcode, delivery_postcode: delivery_postcode,
                weight: weight, cod: cod ? 1 : 0 }
      query[:declared_value] = declared_value.to_f.round(2) if declared_value
      body = request(:get, '/courier/serviceability/', query: query, timeout: timeout)
      data = body.is_a?(Hash) ? body['data'] : nil
      couriers = Array(data.is_a?(Hash) ? data['available_courier_companies'] : nil).filter_map do |c|
        next unless c.is_a?(Hash) && c['courier_company_id'] && c['rate']

        { id: c['courier_company_id'].to_i, name: c['courier_name'].to_s, rate: c['rate'].to_f,
          days: c['estimated_delivery_days'].to_s, etd: c['etd'].to_s }
      end
      recommended = data.is_a?(Hash) ? (data['recommended_courier_company_id'] || data['shiprocket_recommended_courier_id']) : nil
      { couriers: couriers, recommended_id: recommended&.to_i }
    end

    # Pickup addresses saved in the owner's Shiprocket account
    def pickup_locations
      body = request(:get, '/settings/company/pickup')
      list = body.is_a?(Hash) ? body.dig('data', 'shipping_address') : nil
      Array(list).filter_map do |a|
        next unless a.is_a?(Hash) && a['pickup_location'].present?

        { name: a['pickup_location'].to_s, postcode: a['pin_code'].to_s,
          address: [a['address'], a['city'], a['state']].compact_blank.join(', ') }
      end
    end

    def create_order(payload)
      body = request(:post, '/orders/create/adhoc', body: payload)
      raise Error, error_message(body, 'Shiprocket did not create the order') unless body.is_a?(Hash) && body['shipment_id'].present?

      body
    end

    # Returns { awb_code:, courier_name:, courier_id: }
    def assign_awb(shipment_id, courier_id = nil)
      payload = { shipment_id: shipment_id }
      payload[:courier_id] = courier_id if courier_id
      body = request(:post, '/courier/assign/awb', body: payload)
      data = body.is_a?(Hash) ? body.dig('response', 'data') : nil
      unless data.is_a?(Hash) && data['awb_code'].present?
        raise Error, error_message(body, 'No courier could be assigned to this shipment')
      end

      { awb_code: data['awb_code'].to_s, courier_name: data['courier_name'].to_s,
        courier_id: data['courier_company_id']&.to_i }
    end

    def schedule_pickup(shipment_id)
      body = request(:post, '/courier/generate/pickup', body: { shipment_id: [shipment_id] })
      ok = body.is_a?(Hash) && (body['pickup_status'].to_i == 1 || body.dig('response', 'pickup_scheduled_date').present?)
      # Shiprocket answers "Already in Pickup Queue" when the pickup was booked before
      ok ||= error_message(body, '').match?(/already/i)
      raise Error, error_message(body, 'The pickup could not be booked') unless ok

      body
    end

    def label(shipment_id)
      body = request(:post, '/courier/generate/label', body: { shipment_id: [shipment_id] })
      url = body.is_a?(Hash) ? body['label_url'] : nil
      raise Error, error_message(body, 'The label could not be made') if url.blank?

      url.to_s
    end

    def track(awb)
      request(:get, "/courier/track/awb/#{ERB::Util.url_encode(awb)}")
    end

    def cancel(sr_order_id)
      request(:post, '/orders/cancel', body: { ids: [sr_order_id] })
    end

    private

    def token
      if @account.token.blank? || @account.token_expires_at.blank? || @account.token_expires_at < Time.current
        login!
      else
        @account.token
      end
    end

    def request(method, path, query: nil, body: nil, timeout: TIMEOUT, retried: false)
      options = {
        headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
        timeout: timeout
      }
      options[:query] = query if query
      options[:body] = body.to_json if body
      response = HTTParty.send(method, "#{BASE_URL}#{path}", options)

      if response.code == 401 && !retried
        login!
        return request(method, path, query: query, body: body, timeout: timeout, retried: true)
      end
      raise AuthError, 'The Shiprocket login stopped working. Connect Shiprocket again.' if response.code == 401

      parsed = response.parsed_response
      raise Error, error_message(parsed, "Shiprocket error #{response.code}") unless response.success?

      parsed
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
      raise Error, 'Shiprocket did not respond. Please try again in a minute.'
    end

    # Shiprocket's own message, e.g. {"message": "...", "errors": {"billing_phone": ["..."]}}
    def error_message(body, fallback)
      return fallback unless body.is_a?(Hash)

      errors = body['errors'].is_a?(Hash) ? body['errors'].values.flatten.map(&:to_s) : []
      message = body['message'].presence || body.dig('response', 'data').presence
      message = nil unless message.is_a?(String)
      ([message] + errors).compact_blank.uniq.join(' ').presence || fallback
    end
  end
end
