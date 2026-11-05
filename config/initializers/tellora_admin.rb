# frozen_string_literal: true

# Tellora additions to the Spree admin (/admin) of every store.
#
#   Left menu:  "Domain" -> /tellora/domain (connect your own domain, free SSL)
#   Dashboard:  a card showing the store's address and domain status
#
# Spree fills these lists with [] in its own after_initialize, so ours runs after it.
Rails.application.config.after_initialize do
  admin = Rails.application.config.spree_admin
  admin.store_nav_partials << 'spree/admin/shared/tellora_domain_nav' if admin.store_nav_partials.is_a?(Array)
  admin.dashboard_sidebar_partials << 'spree/admin/dashboard/tellora_domain_card' if admin.dashboard_sidebar_partials.is_a?(Array)
rescue StandardError => e
  Rails.logger.warn("[Tellora admin] could not add the Domain menu: #{e.class} - #{e.message}")
end
