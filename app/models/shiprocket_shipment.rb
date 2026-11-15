# frozen_string_literal: true

# A Spree order sent to Shiprocket: its Shiprocket ids, AWB number, courier, label and status.
# Excluded from Apartment: always stored in the public schema (tenant_code says which store).
class ShiprocketShipment < ApplicationRecord
  STEP_LABELS = {
    'new' => 'Sent to Shiprocket',
    'awb_assigned' => 'Courier assigned',
    'pickup_scheduled' => 'Pickup booked'
  }.freeze

  validates :tenant_code, :spree_order_id, :order_number, presence: true

  def self.for_order(order, tenant_code = Apartment::Tenant.current)
    find_by(tenant_code: tenant_code, spree_order_id: order.id)
  end

  def label
    courier_status.presence&.titleize || STEP_LABELS[status] || status.to_s.humanize
  end

  def shipped?
    awb_code.present?
  end

  def tracking_url
    awb_code.present? ? "https://shiprocket.co/tracking/#{awb_code}" : nil
  end

  def delivered?
    delivered_at.present?
  end
end
