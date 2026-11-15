# frozen_string_literal: true

module Platform
  # Shiprocket's tracking webhook: POST /tellora/courier-updates
  # (Shiprocket does not accept webhook URLs containing "shiprocket", "sr" or "kr".)
  #
  # The owner pastes this URL and their store's token into Shiprocket:
  # Settings > API > Webhooks. Shiprocket sends the token in the "x-api-key" header,
  # which tells us which store the update is for.
  #
  # Always answers 200 (Shiprocket stops sending updates after errors), except for a wrong token.
  class CourierUpdatesController < ActionController::Base
    skip_forgery_protection

    def create
      token = request.headers['x-api-key'].to_s
      account = token.length >= 20 ? ShiprocketAccount.find_by(webhook_token: token) : nil
      return head(:unauthorized) unless account

      payload = request.request_parameters.presence || parse_body
      Shiprocket::Shipper.apply_update(payload.to_h.stringify_keys, account) if payload.present?
      head :ok
    rescue StandardError => e
      Rails.logger.error("[Shiprocket] webhook failed: #{e.class} - #{e.message}")
      head :ok
    end

    private

    def parse_body
      JSON.parse(request.raw_post.to_s)
    rescue JSON::ParserError
      {}
    end
  end
end
