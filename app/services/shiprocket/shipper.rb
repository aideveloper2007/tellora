# frozen_string_literal: true

module Shiprocket
  # Sends Spree orders to Shiprocket and ships them. Call inside the store's tenant.
  #
  #   Shipper.new(order).push!   -> creates the order in Shiprocket (it appears in the owner's
  #                                 Shiprocket panel); safe to call twice
  #   Shipper.new(order).ship!   -> push (if needed) + courier & AWB + pickup booking + label
  #   Shipper.apply_update(payload, account) -> courier status from the webhook
  #
  # Errors raise Shiprocket::Client::Error with Shiprocket's own message, and are kept on
  # the ShiprocketShipment row (error) so the owner sees them on the order page.
  class Shipper
    SHIPPED_STATUSES = ['PICKED UP', 'SHIPPED', 'IN TRANSIT', 'OUT FOR DELIVERY', 'DELIVERED', 'REACHED AT DESTINATION HUB',
                        'REACHED DESTINATION HUB', 'OUT FOR PICKUP'].freeze
    PICKED_UP_STATUSES = SHIPPED_STATUSES - ['OUT FOR PICKUP']
    COD_PATTERN = /cash\s*on\s*delivery|\bcod\b|CashOnDelivery/i

    class NotConnected < StandardError; end

    def initialize(order, account = ShiprocketAccount.for_tenant)
      @order = order
      @account = account
      raise NotConnected, 'Connect Shiprocket first (Shipping in the left menu).' unless @account
      raise NotConnected, 'Choose your pickup address on the Shipping page first.' unless @account.ready?
    end

    def record
      @record ||= ShiprocketShipment.find_or_create_by!(tenant_code: @account.tenant_code, spree_order_id: @order.id) do |r|
        r.order_number = @order.number
        r.cod = self.class.cod?(@order)
      end
    end

    def push!
      return record if record.sr_shipment_id.present?

      # Locked, so the order is never created twice (job and owner click at the same moment)
      record.with_lock do
        next if record.sr_shipment_id.present?

        result = step { client.create_order(payload) }
        record.update!(sr_order_id: result['order_id'], sr_shipment_id: result['shipment_id'], status: 'new', error: nil)
      end
      record
    rescue Client::Error => e
      record.update_columns(error: e.message.to_s.truncate(500), updated_at: Time.current) # outside the rolled-back lock
      raise
    end

    def ship!
      push!
      assign_courier! if record.awb_code.blank?
      book_pickup! if record.pickup_scheduled_at.blank?
      make_label! if record.label_url.blank?
      record.update!(error: nil)
      record
    end

    # Is this order paid on delivery? (from its payment method's type or name)
    def self.cod?(order)
      order.payments.reject { |p| %w[failed void invalid].include?(p.state.to_s) }.any? do |payment|
        method = payment.payment_method
        method && "#{method.type} #{method.name}".match?(COD_PATTERN)
      end
    end

    # Courier status from Shiprocket's webhook (payload is the JSON body)
    def self.apply_update(payload, account)
      awb = payload['awb'].to_s.presence
      number = payload['order_id'].to_s.presence
      shipments = ShiprocketShipment.where(tenant_code: account.tenant_code)
      record = (awb && shipments.find_by(awb_code: awb)) || (number && shipments.find_by(order_number: number))
      return nil unless record

      status = payload['current_status'].to_s.upcase.strip.presence || payload['shipment_status'].to_s.upcase.strip
      record.courier_status = status if status.present?
      record.awb_code ||= awb
      record.courier_name ||= payload['courier_name'].presence
      record.last_event = payload.slice('awb', 'current_status', 'shipment_status', 'current_timestamp', 'etd', 'courier_name')
      record.delivered_at ||= Time.current if status == 'DELIVERED'
      record.save!

      mark_spree_shipped(record) if PICKED_UP_STATUSES.include?(status)
      record
    end

    def self.mark_spree_shipped(record)
      Apartment::Tenant.switch(record.tenant_code) do
        order = Spree::Order.find_by(id: record.spree_order_id)
        next unless order

        order.shipments.each do |shipment|
          shipment.update_column(:tracking, record.awb_code) if record.awb_code.present? && shipment.tracking.blank?
          next if shipment.shipped? || shipment.canceled?

          # Ships the Spree shipment (the customer gets Spree's "shipped" email).
          # COD orders are not paid yet, so Spree keeps them "pending"; their status stays visible on the order page.
          shipment.ship! if shipment.ready? && shipment.can_ship?
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[Shiprocket] could not mark order #{record.order_number} shipped: #{e.class} - #{e.message}")
    end

    private

    def client
      @client ||= @account.client
    end

    # Runs a Shiprocket call; keeps the error on the record for the order page
    def step
      yield
    rescue StandardError => e
      record.update_columns(error: e.message.to_s.truncate(500), updated_at: Time.current)
      raise e.is_a?(Client::Error) ? e : Client::Error.new(e.message)
    end

    def assign_courier!
      parcel = parcel_for_order
      courier_id = step do
        result = client.rates(pickup_postcode: @account.pickup_postcode, delivery_postcode: postcode,
                              weight: parcel[:weight], cod: record.cod, declared_value: @order.total, timeout: Client::TIMEOUT)
        raise Client::Error, "No courier delivers to pincode #{postcode} for this order." if result[:couriers].empty?

        (result[:couriers].find { |c| c[:id] == result[:recommended_id] } || result[:couriers].min_by { |c| c[:rate] })[:id]
      end

      awb = step { client.assign_awb(record.sr_shipment_id, courier_id) }
      record.update!(awb_code: awb[:awb_code], courier_name: awb[:courier_name], courier_id: awb[:courier_id] || courier_id,
                     status: 'awb_assigned')
      @order.shipments.each { |s| s.update_column(:tracking, awb[:awb_code]) }
    end

    def book_pickup!
      step { client.schedule_pickup(record.sr_shipment_id) }
      record.update!(status: 'pickup_scheduled', pickup_scheduled_at: Time.current)
    end

    def make_label!
      url = step { client.label(record.sr_shipment_id) }
      record.update!(label_url: url)
    end

    def postcode
      (@order.ship_address&.zipcode || @order.bill_address&.zipcode).to_s.gsub(/\D/, '')
    end

    def parcel_for_order
      @parcel_for_order ||= Parcel.for_items(@order.line_items.map { |item| [item.variant, item.quantity] })
    end

    def payload
      ship = @order.ship_address || @order.bill_address
      bill = @order.bill_address || ship
      raise Client::Error, 'This order has no delivery address.' unless ship

      parcel = parcel_for_order
      same = bill.nil? || address_fields(bill) == address_fields(ship)
      data = {
        order_id: @order.number,
        order_date: (@order.completed_at || @order.created_at).in_time_zone('Asia/Kolkata').strftime('%Y-%m-%d %H:%M'),
        pickup_location: @account.pickup_location,
        comment: "Tellora order #{@order.number}",
        shipping_is_billing: same,
        order_items: @order.line_items.map { |item| order_item(item) },
        payment_method: record.cod ? 'COD' : 'Prepaid',
        shipping_charges: @order.shipment_total.to_f.round(2),
        total_discount: (-@order.promo_total.to_f).clamp(0, Float::INFINITY).round(2),
        sub_total: (@order.item_total.to_f + @order.additional_tax_total.to_f).round(2),
        length: parcel[:length], breadth: parcel[:breadth], height: parcel[:height], weight: parcel[:weight]
      }
      data.merge!(address_fields(bill || ship, 'billing'))
      data.merge!(address_fields(ship, 'shipping')) unless same
      data
    end

    def order_item(item)
      variant = item.variant
      {
        name: variant.try(:descriptive_name).presence || variant.name,
        sku: variant.sku.presence || "TL-#{variant.id}",
        units: item.quantity,
        selling_price: item.price.to_f.round(2),
        discount: 0,
        tax: 0
      }
    end

    def address_fields(address, prefix = nil)
      first = address.try(:firstname) || address.try(:first_name)
      last = address.try(:lastname) || address.try(:last_name)
      fields = {
        customer_name: first.to_s.presence || 'Customer',
        last_name: last.to_s,
        address: address.address1.to_s,
        address_2: address.address2.to_s,
        city: address.city.to_s,
        pincode: address.zipcode.to_s.gsub(/\D/, ''),
        state: address.state&.name || address.try(:state_name).to_s,
        country: address.country&.name || 'India',
        email: @order.email.to_s,
        phone: address.phone.to_s.gsub(/\D/, '').last(10)
      }
      return fields unless prefix

      fields.transform_keys { |k| :"#{prefix}_#{k}" }
    end
  end
end
