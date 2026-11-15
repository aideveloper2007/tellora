# frozen_string_literal: true

# Sends a completed order to the store's Shiprocket account, so it appears in their
# Shiprocket panel straight away. Only paid orders and cash-on-delivery orders are sent.
# Shipping itself (courier, pickup, label) happens when the owner clicks
# "Ship with Shiprocket" on the order page.
class ShiprocketOrderJob
  include Sidekiq::Job
  sidekiq_options retry: 3

  def perform(tenant_code, order_id)
    account = ShiprocketAccount.for_tenant(tenant_code)
    return unless account&.auto_push && account.ready?

    Apartment::Tenant.switch(tenant_code) do
      order = Spree::Order.find_by(id: order_id)
      return unless order&.completed?
      return unless order.paid? || Shiprocket::Shipper.cod?(order)

      Shiprocket::Shipper.new(order, account).push!
    end
  rescue Shiprocket::Client::AuthError, Shiprocket::Shipper::NotConnected => e
    Rails.logger.warn("[Shiprocket] order #{order_id} (#{tenant_code}) not sent: #{e.message}")
  end
end
