# frozen_string_literal: true

# Tellora additions to the Spree admin (/admin) of every store.
#
#   Left menu:   "Domain"     -> /tellora/domain   (connect your own domain, free SSL)
#                "Shiprocket" -> /tellora/shipping (connect Shiprocket, live courier rates)
#   Dashboard:   a card showing the store's address and domain status
#   Order page:  a Shiprocket card (ship, label, tracking)
#   Shipping:    the "Shiprocket live courier rate" calculator for shipping methods
#
# Spree fills these lists with [] in its own after_initialize, so ours runs after it.
Rails.application.config.after_initialize do
  admin = Rails.application.config.spree_admin
  admin.store_nav_partials << 'spree/admin/shared/tellora_domain_nav' if admin.store_nav_partials.is_a?(Array)
  admin.store_nav_partials << 'spree/admin/shared/tellora_shipping_nav' if admin.store_nav_partials.is_a?(Array)
  admin.dashboard_sidebar_partials << 'spree/admin/dashboard/tellora_domain_card' if admin.dashboard_sidebar_partials.is_a?(Array)
  if admin.respond_to?(:order_page_sidebar_partials) && admin.order_page_sidebar_partials.is_a?(Array)
    admin.order_page_sidebar_partials << 'spree/admin/orders/tellora_shiprocket'
  else
    Rails.logger.warn('[Tellora admin] order page sidebar not available: Shiprocket card not added')
  end
rescue StandardError => e
  Rails.logger.warn("[Tellora admin] could not add the Tellora menus: #{e.class} - #{e.message}")
end

Rails.application.config.after_initialize do
  calculators = Rails.application.config.spree.calculators.shipping_methods
  calculators << Spree::Calculator::Shipping::ShiprocketRate unless calculators.include?(Spree::Calculator::Shipping::ShiprocketRate)
rescue StandardError => e
  Rails.logger.warn("[Tellora admin] could not add the Shiprocket calculator: #{e.class} - #{e.message}")
end