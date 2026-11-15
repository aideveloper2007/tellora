# frozen_string_literal: true

# When an order is completed, send it to the store's Shiprocket account (if connected).
# The job runs 30 seconds later, so the payment state is final.
module Spree
  module OrderShiprocketDecorator
    def self.prepended(base)
      # Added once, even when this file is loaded again in development
      return if base.instance_variable_get(:@tellora_shiprocket_hook)

      base.state_machine.after_transition to: :complete, do: :queue_shiprocket_order
      base.instance_variable_set(:@tellora_shiprocket_hook, true)
    end

    private

    def queue_shiprocket_order
      tenant = Apartment::Tenant.current
      return if tenant.blank? || tenant == 'public'
      return unless ShiprocketAccount.where(tenant_code: tenant).exists?

      ShiprocketOrderJob.perform_in(30, tenant, id)
    rescue StandardError => e
      Rails.logger.warn("[Shiprocket] could not queue order #{number}: #{e.class} - #{e.message}")
    end
  end
end

Spree::Order.prepend(Spree::OrderShiprocketDecorator) unless Spree::Order.ancestors.include?(Spree::OrderShiprocketDecorator)
