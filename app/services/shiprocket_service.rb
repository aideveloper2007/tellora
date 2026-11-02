class ShiprocketService
  include HTTParty
  base_uri 'https://apiv2.shiprocket.in/v1/external'

  # -----------------------------
  # Step 1: Login to Shiprocket
  # -----------------------------
  def self.login
    setting = ShiprocketSetting.last
    return unless setting

    response = post(
      '/auth/login',
      headers: { "Content-Type" => "application/json" },
      body: { email: setting.email, password: setting.password }.to_json
    )

    if response.code == 200 && response.parsed_response["token"].present?
      token = response.parsed_response["token"]
      # Save token in cache for 6 hours
      Rails.cache.write("shiprocket_token", token, expires_in: 6.hours)
      token
    else
      Rails.logger.error("Shiprocket login failed: #{response.body}")
      nil
    end
  end

  # -----------------------------
  # Step 2: Get token (cached)
  # -----------------------------
  def self.token
    # Try to fetch existing token from cache
    Rails.cache.read("shiprocket_token") || login
  end

  # -----------------------------
  # Step 3: Create Order
  # -----------------------------

  def self.create_order(payload)
    token = self.token
    return unless token

    response = post(
      '/orders/create/adhoc',
      headers: {
        "Authorization" => "Bearer #{token}",
        "Content-Type" => "application/json"
      },
      body: payload.to_json
    )
    if response.code == 200 
      Rails.logger.info("Shiprocket order created successfully: #{response.parsed_response}")
      { success: true, message: "Order successfully created in Shiprocket", data: response.parsed_response }
    else
      Rails.logger.error("Shiprocket create order failed: #{response.body}")
      { success: false, message: "Failed to create order in Shiprocket", error: response.parsed_response }
    end
  end

end