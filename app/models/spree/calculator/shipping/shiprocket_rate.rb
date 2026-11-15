# frozen_string_literal: true

module Spree
  module Calculator::Shipping
    # Live courier rate from Shiprocket at checkout.
    #
    # Uses the store's Shiprocket account: pickup pincode -> customer's pincode, with the
    # parcel weight from the products. Shown only when a courier delivers to that pincode.
    # Uses the recommended courier's rate (the one used when shipping), else the cheapest.
    # If Shiprocket does not answer, the store's fallback rate is used, so checkout never stops.
    # Rates are cached for 10 minutes (same pincode and weight).
    class ShiprocketRate < ShippingCalculator
      CACHE_FOR = 10.minutes
      ERROR_CACHE_FOR = 1.minute

      def self.description
        'Shiprocket live courier rate'
      end

      def available?(package)
        quote = quote_for(package)
        quote.present? && quote[:available]
      end

      def compute_package(package)
        quote = quote_for(package)
        quote ? quote[:rate] : nil
      end

      private

      # { available:, rate:, courier_id:, courier_name:, days: } or nil
      def quote_for(package)
        account = ShiprocketAccount.for_tenant
        return nil unless account&.ready?

        address = package.order&.ship_address
        postcode = address&.zipcode.to_s.gsub(/\D/, '')
        return nil unless postcode.length == 6
        return nil if address.country && address.country.iso != 'IN'

        parcel = Shiprocket::Parcel.for_items(package.contents.map { |item| [item.variant, item.quantity] })
        key = ['tellora', 'shiprocket-rate', account.tenant_code, account.pickup_postcode, postcode, parcel[:weight]].join(':')

        cached = Rails.cache.read(key)
        return cached if cached

        quote = fetch_quote(account, postcode, parcel, package.order)
        Rails.cache.write(key, quote, expires_in: quote[:fallback] ? ERROR_CACHE_FOR : CACHE_FOR)
        quote
      end

      def fetch_quote(account, postcode, parcel, order)
        result = account.client.rates(pickup_postcode: account.pickup_postcode, delivery_postcode: postcode,
                                      weight: parcel[:weight], cod: false, declared_value: order&.item_total)
        couriers = result[:couriers]
        return { available: false } if couriers.empty?

        chosen = couriers.find { |c| c[:id] == result[:recommended_id] } || couriers.min_by { |c| c[:rate] }
        { available: true, rate: chosen[:rate].ceil, courier_id: chosen[:id], courier_name: chosen[:name], days: chosen[:days] }
      rescue StandardError => e
        Rails.logger.warn("[Shiprocket] rate for #{postcode} failed (#{e.class}: #{e.message}), using the fallback rate")
        { available: true, rate: account.fallback_rate.to_f, fallback: true }
      end
    end
  end
end
