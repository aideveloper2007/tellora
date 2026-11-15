# frozen_string_literal: true

module Shiprocket
  # Sets up a store's checkout for Shiprocket (call inside the store's tenant):
  #   - an "India" shipping zone
  #   - a "Standard delivery (Shiprocket)" shipping method with live courier rates,
  #     for every shipping category, with Shiprocket's tracking link
  #
  #   Setup.install!   (when the owner connects Shiprocket; safe to run again)
  #   Setup.remove!    (when the owner disconnects)
  module Setup
    CODE = 'tellora_shiprocket'
    NAME = 'Standard delivery'
    TRACKING_URL = 'https://shiprocket.co/tracking/:tracking'

    module_function

    def install!
      zone = india_zone
      categories = Spree::ShippingCategory.all.to_a
      categories = [Spree::ShippingCategory.create!(name: 'Default')] if categories.empty?

      method = Spree::ShippingMethod.find_by(code: CODE) || Spree::ShippingMethod.new(code: CODE)
      method.name = NAME
      method.admin_name = 'Shiprocket (live courier rates)' if method.respond_to?(:admin_name=)
      method.display_on = 'both' if method.respond_to?(:display_on=)
      method.tracking_url = TRACKING_URL if method.respond_to?(:tracking_url=)
      method.shipping_categories = categories
      method.zones = [zone]
      method.calculator = Spree::Calculator::Shipping::ShiprocketRate.new unless method.calculator.is_a?(Spree::Calculator::Shipping::ShiprocketRate)
      method.save!
      method
    end

    def remove!
      Spree::ShippingMethod.where(code: CODE).find_each(&:destroy)
    end

    def india_zone
      india = Spree::Country.find_by(iso: 'IN') or raise 'India is missing from the store\'s countries'
      zone = Spree::Zone.joins(:zone_members)
                        .where(spree_zone_members: { zoneable_type: 'Spree::Country', zoneable_id: india.id })
                        .where(kind: 'country')
                        .first
      return zone if zone

      zone = Spree::Zone.find_or_create_by!(name: 'India') do |z|
        z.description = 'India (Shiprocket)'
        z.kind = 'country'
      end
      zone.zone_members.find_or_create_by!(zoneable: india)
      zone
    end
  end
end
