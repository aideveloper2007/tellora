# frozen_string_literal: true

module Platform
  # The owner's "Shipping" screen (/tellora/shipping), on the store's own address.
  # Connects the owner's own Shiprocket account (an API user), picks the pickup address,
  # and adds Shiprocket's live courier rates to checkout.
  # Also the "Ship with Shiprocket" button on the admin order page.
  #
  # Uses the builder's owner check (load_build, require_owner).
  class ShippingController < BuilderController
    before_action :load_account

    # GET /tellora/shipping
    def show
      @pickups = []
      @pickup_error = nil
      if @account
        begin
          @pickups = @account.client.pickup_locations
        rescue Shiprocket::Client::Error => e
          @pickup_error = e.message
        end
      end
      @shipments = @account ? ShiprocketShipment.where(tenant_code: @account.tenant_code).order(updated_at: :desc).limit(10) : []
      @no_weight = products_without_weight
      @webhook_url = "#{request.base_url}#{platform_courier_updates_path}"
    end

    # POST /tellora/shipping  { email:, password: }  (connect)
    def create
      return redirect_to(platform_shipping_path) if @account

      account = ShiprocketAccount.new(store_id: @build.store_id, tenant_code: @build.tenant_code,
                                      email: params[:email].to_s.strip.downcase)
      account.password = params[:password].to_s
      return redirect_to(platform_shipping_path, alert: account.errors.full_messages.to_sentence) unless account.valid?

      account.client.login!
      pickups = account.client.pickup_locations
      if pickups.size == 1
        account.pickup_location = pickups.first[:name]
        account.pickup_postcode = pickups.first[:postcode]
      end
      account.connected_at = Time.current
      account.save!
      Shiprocket::Setup.install!

      notice = account.ready? ? 'Shiprocket is connected. Checkout now shows live courier rates.' : 'Shiprocket is connected. Now choose your pickup address.'
      redirect_to platform_shipping_path, notice: notice
    rescue Shiprocket::Client::Error => e
      redirect_to platform_shipping_path, alert: e.message
    rescue StandardError => e
      Rails.logger.error("[Shipping] connect failed: #{e.class} - #{e.message}")
      redirect_to platform_shipping_path, alert: 'Shiprocket could not be connected. Please try again.'
    end

    # PATCH /tellora/shipping  { pickup_location:, fallback_rate:, auto_push: }
    def update
      return redirect_to(platform_shipping_path) unless @account

      if params[:pickup_location].present?
        pickup = @account.client.pickup_locations.find { |p| p[:name] == params[:pickup_location].to_s }
        return redirect_to(platform_shipping_path, alert: 'That pickup address was not found in Shiprocket.') unless pickup

        @account.pickup_location = pickup[:name]
        @account.pickup_postcode = pickup[:postcode]
      end
      @account.fallback_rate = params[:fallback_rate] if params.key?(:fallback_rate)
      @account.auto_push = params[:auto_push] == '1' if params.key?(:auto_push)

      if @account.save
        redirect_to platform_shipping_path, notice: 'Shipping settings saved.'
      else
        redirect_to platform_shipping_path, alert: @account.errors.full_messages.to_sentence
      end
    rescue Shiprocket::Client::Error => e
      redirect_to platform_shipping_path, alert: e.message
    end

    # DELETE /tellora/shipping  (disconnect)
    def destroy
      return redirect_to(platform_shipping_path) unless @account

      Shiprocket::Setup.remove!
      @account.destroy
      redirect_to platform_shipping_path, notice: 'Shiprocket was disconnected. Checkout no longer shows Shiprocket rates.'
    end

    # POST /tellora/shipping/orders/:number/ship  ("Ship with Shiprocket" on the admin order page)
    def ship
      order = Spree::Order.complete.find_by(number: params[:number].to_s)
      return redirect_back(fallback_location: '/admin/orders', alert: 'Order not found.') unless order

      record = Shiprocket::Shipper.new(order, @account).ship!
      flash[:success] = "Shipped with #{record.courier_name.presence || 'Shiprocket'}. AWB #{record.awb_code}. Pickup booked."
      redirect_back fallback_location: "/admin/orders/#{order.number}/edit"
    rescue Shiprocket::Shipper::NotConnected, Shiprocket::Client::Error => e
      flash[:error] = "Shiprocket: #{e.message}"
      redirect_back fallback_location: (order ? "/admin/orders/#{order.number}/edit" : '/admin/orders')
    end

    private

    def load_account
      @account = ShiprocketAccount.for_tenant(@build.tenant_code)
    end

    def products_without_weight
      Spree::Variant.joins(:product)
                    .where(spree_products: { deleted_at: nil })
                    .where('spree_variants.weight IS NULL OR spree_variants.weight = 0')
                    .where('spree_variants.is_master = ? OR NOT EXISTS (SELECT 1 FROM spree_variants v2 WHERE v2.product_id = spree_variants.product_id AND v2.is_master = ? AND v2.deleted_at IS NULL)', false, false)
                    .count
    rescue StandardError
      0
    end
  end
end
