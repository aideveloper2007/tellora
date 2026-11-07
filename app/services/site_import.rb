# frozen_string_literal: true

require 'open-uri'

# "Move my store": reads the owner's existing online store through the GenAI
# Theme API (POST /api/v1/site-import) and brings its brand into Tellora.
#
# The new store opens on its Tellora subdomain. The owner connects their own
# domain later, from the Domain screen (which checks DNS).
#
#   SiteImport.read(build)              # => { 'brand' => {...}, 'plan' => {...}, 'images' => {...}, 'description' => '...' }
#   SiteImport.attach_logo(store, url)  # their logo becomes the store logo (inside the store's tenant)
class SiteImport
  REQUEST_TIMEOUT = 180 # seconds: reading the site + writing the page plan
  MAX_LOGO_BYTES = 5 * 1024 * 1024

  class Failed < StandardError; end

  class << self
    def read(build)
      url = "#{ENV.fetch('GENAI_SERVICE_URL', 'http://localhost:8000')}/api/v1/site-import"
      response = HTTParty.post(
        url,
        body: {
          url: build.source_url,
          store_name: build.store_name,
          currency: build.currency,
          families: StyleFamily.catalogue
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: REQUEST_TIMEOUT
      )
      raise Failed, error_message(response) unless response.success?

      data = response.parsed_response
      raise Failed, 'nothing came back from your store' unless data.is_a?(Hash) && data['plan'].is_a?(Hash)

      data.slice('brand', 'plan', 'images', 'description')
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise Failed, 'reading your store took too long'
    rescue Errno::ECONNREFUSED
      raise Failed, 'the design service did not respond'
    end

    # Their logo becomes the store logo. Call inside the store's tenant. Never raises.
    def attach_logo(store, logo_url)
      return if logo_url.blank? || !logo_url.to_s.start_with?('https://')
      return unless store.respond_to?(:logo)
      return if store.logo.attached?

      io = URI.open(logo_url, read_timeout: 20, open_timeout: 10, 'User-Agent' => 'TelloraImporter/1.0')
      return if io.size > MAX_LOGO_BYTES

      content_type = io.content_type.to_s
      return unless content_type.start_with?('image/')

      extension = Rack::Mime::MIME_TYPES.invert[content_type] || '.png'
      store.logo.attach(io: io, filename: "logo#{extension}", content_type: content_type)
    rescue StandardError => e
      Rails.logger.warn("[SiteImport] logo not attached (#{logo_url}): #{e.class} - #{e.message}")
      nil
    end

    private

    def error_message(response)
      body = response.parsed_response
      detail = body.is_a?(Hash) ? body['detail'] : nil
      message = detail.is_a?(Hash) ? detail.dig('error', 'message') : nil
      message.presence || "the store reader answered with error #{response.code}"
    end
  end
end