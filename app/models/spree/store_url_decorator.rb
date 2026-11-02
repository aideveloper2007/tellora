# frozen_string_literal: true

# Spree builds every storefront link (menus, footer, canonical tag) from
# Store#formatted_url. In production it always uses https and no port, which
# breaks links when the app runs on a local port such as http://...:3002.
#
# Set these only for local or test machines (docker-compose.local.yml):
#   STORE_URL_PROTOCOL=http
#   STORE_URL_PORT=3002
# On a real server leave them unset and Spree's normal https links are used.
module Spree
  module StoreUrlDecorator
    def formatted_url
      protocol = ENV['STORE_URL_PROTOCOL'].to_s.strip.downcase
      return super if protocol.blank?

      @formatted_url ||= begin
        host = url.to_s.sub(%r{\Ahttps?://}, '').split('/').first.to_s.split(':').first
        port = ENV['STORE_URL_PORT'].to_s.strip.presence&.to_i
        builder = protocol == 'https' ? URI::HTTPS : URI::HTTP
        builder.build(host: host, port: port).to_s
      end
    end
  end

  Store.prepend(StoreUrlDecorator) unless Store.ancestors.include?(StoreUrlDecorator)
end
