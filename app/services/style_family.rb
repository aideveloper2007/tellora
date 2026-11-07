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
#
# A store moved from another platform also gets its own brand on top of the
# family: its accent colour and its fonts (see .clean_brand).
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
      swatch: { background: '#efe6da', ink: '#1f1510', accent: '#8e2a22', display: "'Fraunces', Georgia, serif" },
      vars: { accent: '--wa-cherry', accent_dark: '--wa-cherry-dark', display: '--wa-display', body: '--wa-body', button_rgb: true }
    },
    'editorial_luxury' => {
      name: 'Editorial Luxury',
      version: 1,
      fonts: 'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&family=Manrope:wght@400;500;600&display=swap',
      fits: 'Fashion, clothing, shoes, bags, beauty, skincare, perfume, lifestyle and design-led brands',
      summary: 'Ivory and olive, big photos. Like a fashion magazine.',
      swatch: { background: '#fbfaf8', ink: '#161514', accent: '#3e4436', display: "'Cormorant Garamond', Georgia, serif" },
      vars: { accent: '--el-olive', accent_dark: '--el-olive-dark', display: '--el-display', body: '--el-body' }
    },
    'modern_minimal' => {
      name: 'Modern Minimal',
      version: 1,
      fonts: 'https://fonts.googleapis.com/css2?family=Marcellus&family=Jost:wght@300;400;500&display=swap',
      fits: 'Jewellery, watches, accessories, cosmetics, gifts, electronics, home decor and anything small and precious',
      summary: 'White space, soft stone and gold. Arched photo frames.',
      swatch: { background: '#f5f3f0', ink: '#232120', accent: '#a8834d', display: "'Marcellus', Georgia, serif" },
      vars: { accent: '--mm-gold', accent_dark: '--mm-gold-dark', display: '--mm-display', body: '--mm-body' }
    }
  }.freeze

  DEFAULT = 'warm_artisan'

  HEX_COLOR = /\A#\h{6}\z/
  FONT_NAME = /\A[A-Za-z0-9 ]{2,40}\z/
  FONT_SPEC = /\A[A-Za-z0-9+]{2,60}(:wght@[0-9;]{3,20})?\z/

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

    # The HTML placed in <head> for a family (plus the store's own brand, if any)
    def head_code(key, brand: nil)
      key = resolve(key)
      family = FAMILIES.fetch(key)
      brand = clean_brand(brand)
      lines = [
        START_MARK,
        %(<link rel="preconnect" href="https://fonts.googleapis.com">),
        %(<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>),
        %(<link rel="stylesheet" href="#{family[:fonts]}">),
        %(<link rel="stylesheet" href="/families/#{key}.css?v=#{family[:version]}">)
      ]
      lines.concat(brand_code(family, brand)) if brand.present?
      lines << END_MARK
      lines.join("\n")
    end

    # Only safe, known values from an imported brand: a hex accent colour and
    # Google Fonts that exist. Anything else is dropped. Returns a plain Hash or {}.
    def clean_brand(raw)
      return {} unless raw.is_a?(Hash)

      raw = raw.deep_stringify_keys
      out = {}
      accent = raw['accent'].to_s.downcase
      out['accent'] = accent if accent.match?(HEX_COLOR)

      # As read from a site: { 'fonts' => { 'display' => {...} } }; as stored: { 'display' => {...} }
      fonts = raw['fonts'].is_a?(Hash) ? raw['fonts'] : raw
      %w[display body].each do |role|
        font = fonts[role].is_a?(Hash) ? fonts[role] : {}
        name = font['name'].to_s
        spec = font['spec'].to_s
        next unless name.match?(FONT_NAME) && spec.match?(FONT_SPEC)

        out[role] = { 'name' => name, 'spec' => spec }
      end
      out
    end

    # Put the family into the store's head code, replacing any earlier family block.
    # Spree::Store lives in the public schema, so this works from any tenant.
    def install!(store, key, brand: nil)
      existing = store.storefront_custom_code_head.to_s.gsub(BLOCK_PATTERN, "\n").strip
      code = [head_code(key, brand: brand), existing.presence].compact.join("\n")
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

    private

    # The store's own accent colour and fonts, on top of the family's variables
    def brand_code(family, brand)
      vars = family[:vars]
      lines = []
      specs = %w[display body].filter_map { |role| brand.dig(role, 'spec') }.uniq
      if specs.any?
        lines << %(<link rel="stylesheet" href="https://fonts.googleapis.com/css2?#{specs.map { |s| "family=#{s}" }.join('&')}&display=swap">)
      end

      rules = []
      if (accent = brand['accent'])
        rules << "#{vars[:accent]}: #{accent};"
        rules << "#{vars[:accent_dark]}: #{shade(accent, 0.82)};"
        if vars[:button_rgb]
          r, g, b = rgb(accent)
          rules << "--button-rgb: #{r}, #{g}, #{b} !important;"
        end
      end
      rules << "#{vars[:display]}: '#{brand.dig('display', 'name')}', Georgia, serif;" if brand['display']
      rules << "#{vars[:body]}: '#{brand.dig('body', 'name')}', 'Segoe UI', system-ui, sans-serif;" if brand['body']
      lines << "<style>:root { #{rules.join(' ')} }</style>" if rules.any?
      lines
    end

    def rgb(hex)
      [hex[1, 2], hex[3, 2], hex[5, 2]].map { |part| part.to_i(16) }
    end

    # Darker version of a colour (factor 0.82 = 18% darker), for hover states
    def shade(hex, factor)
      format('#%02x%02x%02x', *rgb(hex).map { |c| (c * factor).round.clamp(0, 255) })
    end
  end
end