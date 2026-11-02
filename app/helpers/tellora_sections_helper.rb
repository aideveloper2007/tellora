# frozen_string_literal: true

# Helpers for the designer-made home page sections (app/views/storefront_sections).
# The markup is shared by every style family; each family's stylesheet
# (public/families/<family>.css) gives it its own look.
module TelloraSectionsHelper
  ICON_PATHS = {
    'leaf' => '<path d="M5 19c0-8 5-13 14-14-1 9-6 14-14 14Z"/><path d="M5 19 13 11"/>',
    'truck' => '<path d="M3 7h11v9H3zM14 10h4l3 3v3h-7"/><circle cx="7" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
    'calendar' => '<rect x="4" y="5" width="16" height="15" rx="1"/><path d="M4 10h16M9 3v4M15 3v4"/>',
    'pin' => '<path d="M12 21c-4-3-7-6.5-7-10a7 7 0 0 1 14 0c0 3.5-3 7-7 10Z"/><circle cx="12" cy="11" r="2.5"/>',
    'shield' => '<path d="M12 3 5 6v5c0 4.5 3 8 7 10 4-2 7-5.5 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-4"/>',
    'gift' => '<rect x="4" y="9" width="16" height="11" rx="1"/><path d="M3 9h18M12 9v11M12 9c-2-4-6-4-6-1.5S10 9 12 9Zm0 0c2-4 6-4 6-1.5S14 9 12 9Z"/>',
    'star' => '<path d="m12 4 2.4 5 5.6.8-4 3.9 1 5.5-5-2.7-5 2.7 1-5.5-4-3.9 5.6-.8L12 4Z"/>',
    'return' => '<path d="M9 7 5 11l4 4"/><path d="M5 11h9a5 5 0 0 1 0 10h-3"/>',
    'heart' => '<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z"/>',
    'sparkle' => '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
    'hand' => '<path d="M8 13V6a1.5 1.5 0 0 1 3 0v6M11 11V4.5a1.5 1.5 0 0 1 3 0V11M14 11V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-.5A6.5 6.5 0 0 1 4 15.5L3 12a1.5 1.5 0 0 1 2.8-1L8 14"/>',
    'clock' => '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3 2"/>'
  }.freeze

  def tl_icon(name)
    paths = ICON_PATHS[name.to_s] || ICON_PATHS['sparkle']
    %(<svg class="tl-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">#{paths}</svg>).html_safe
  end

  # URL of a section photo (ThemeImage) or product photo (Spree::Image), cropped to size
  def tl_image_url(image, width:, height:)
    return if image.nil?

    target = image.is_a?(ThemeImage) ? image.image : image
    return if target.respond_to?(:attached?) && !target.attached?

    spree_image_url(target, width: width, height: height).presence || main_app.url_for(target)
  rescue StandardError => e
    Rails.logger.warn("[TelloraSections] image url failed: #{e.class} - #{e.message}")
    nil
  end

  def tl_price(product)
    price = product.price_in(current_currency)
    (price&.amount.present? ? price.display_price : product.display_price).to_s
  rescue StandardError
    ''
  end

  # One short line under the product name: the first sentence of its description
  def tl_product_note(product)
    text = strip_tags(product.description.to_s).squish
    return '' if text.blank?

    sentence = text.split(/(?<=[.!?])\s/).first.to_s
    sentence.truncate(80, separator: ' ')
  end

  def tl_product_category(product)
    taxon = product.taxons.detect { |t| t.parent_id.present? } || product.taxons.first
    taxon&.name.to_s
  end
end
