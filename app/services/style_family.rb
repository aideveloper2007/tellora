# frozen_string_literal: true

# Designer-made style families for Tellora stores.
#
# A family is a complete, hand-built look (fonts, colours, spacing, product card,
# header, footer and home page sections). The AI never writes CSS: it only picks
# a family and writes the words and photo searches for the sections.
#
# The family stylesheet reaches every storefront page through the store's
# "custom code in <head>" field, inside marker comments. Anything the owner has
# written in that field outside the markers is kept untouched.
class StyleFamily
  START_MARK = '<!-- tellora:style-family:start -->'
  END_MARK   = '<!-- tellora:style-family:end -->'
  BLOCK_PATTERN = /\n?#{Regexp.escape(START_MARK)}.*?#{Regexp.escape(END_MARK)}\n?/m

  FAMILIES = {
    'warm_artisan' => {
      name: 'Warm Artisan',
      version: 1,
      fonts: 'https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400;0,9..144,600;0,9..144,700;1,9..144,400&family=Karla:wght@400;500;600;700&display=swap',
      fits: 'Food, coffee, tea, bakery, handmade goods, crafts, candles, ceramics, organic and farm products, home and kitchen',
      summary: 'Kraft paper, espresso and cherry red. Warm and handmade.',
      swatch: { background: '#efe6da', ink: '#1f1510', accent: '#8e2a22', display: "'Fraunces', Georgia, serif" }
    },
    'editorial_luxury' => {
      name: 'Editorial Luxury',
      version: 1,
      fonts: 'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&family=Manrope:wght@400;500;600&display=swap',
      fits: 'Fashion, clothing, shoes, bags, beauty, skincare, perfume, lifestyle and design-led brands',
      summary: 'Ivory and olive, big photos. Like a fashion magazine.',
      swatch: { background: '#fbfaf8', ink: '#161514', accent: '#3e4436', display: "'Cormorant Garamond', Georgia, serif" }
    },
    'modern_minimal' => {
      name: 'Modern Minimal',
      version: 1,
      fonts: 'https://fonts.googleapis.com/css2?family=Marcellus&family=Jost:wght@300;400;500&display=swap',
      fits: 'Jewellery, watches, accessories, cosmetics, gifts, electronics, home decor and anything small and precious',
      summary: 'White space, soft stone and gold. Arched photo frames.',
      swatch: { background: '#f5f3f0', ink: '#232120', accent: '#a8834d', display: "'Marcellus', Georgia, serif" }
    }
  }.freeze

  DEFAULT = 'warm_artisan'

  class << self
    def known?(key)
      FAMILIES.key?(key.to_s)
    end

    def keys
      FAMILIES.keys
    end

    # Short list sent to the AI so it can choose a family
    def catalogue
      FAMILIES.map { |key, f| { 'key' => key, 'name' => f[:name], 'fits' => f[:fits] } }
    end

    def resolve(key)
      known?(key) ? key.to_s : DEFAULT
    end

    # The HTML placed in <head> for a family
    def head_code(key)
      key = resolve(key)
      family = FAMILIES.fetch(key)
      [
        START_MARK,
        %(<link rel="preconnect" href="https://fonts.googleapis.com">),
        %(<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>),
        %(<link rel="stylesheet" href="#{family[:fonts]}">),
        %(<link rel="stylesheet" href="/families/#{key}.css?v=#{family[:version]}">),
        END_MARK
      ].join("\n")
    end

    # Put the family into the store's head code, replacing any earlier family block.
    # Spree::Store lives in the public schema, so this works from any tenant.
    def install!(store, key)
      existing = store.storefront_custom_code_head.to_s.gsub(BLOCK_PATTERN, "\n").strip
      code = [head_code(key), existing.presence].compact.join("\n")
      store.update_columns(storefront_custom_code_head: code, updated_at: Time.current)
      store.touch
    end

    # Take the family out again, keeping the owner's own code
    def remove!(store)
      existing = store.storefront_custom_code_head.to_s.gsub(BLOCK_PATTERN, "\n").strip
      store.update_columns(storefront_custom_code_head: existing.presence, updated_at: Time.current)
      store.touch
    end

    # Google Fonts for the style picker cards (all families in one request)
    def all_fonts_url
      families = FAMILIES.values.flat_map { |f| f[:fonts][/css2\?(.*)&display=/, 1].to_s.split('&') }
      "https://fonts.googleapis.com/css2?#{families.uniq.join('&')}&display=swap"
    end

    def installed_key(store)
      store.storefront_custom_code_head.to_s[%r{/families/([a-z_]+)\.css}, 1]
    end
  end
end