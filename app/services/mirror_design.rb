# frozen_string_literal: true

# A store design rebuilt from the owner's screenshots ("Move my store").
#
# The design (from ScreenshotImport) has the owner's header, home page and footer
# as HTML and CSS. It reaches the storefront like this:
#   head code        -> their fonts and CSS, plus CSS that hides Spree's own header,
#                       announcement bar, newsletter and footer
#   body start code  -> their header      (every page)
#   body end code    -> their footer      (every page)
#   home page        -> their page content, with the product grid filled with real products
#
# Everything is inside marker comments, so the owner's own custom code is kept.
# Their images are saved as ThemeImage records of the theme (sections "mirror_<id>").
class MirrorDesign
  START_MARK = '<!-- tellora:mirror:start -->'
  END_MARK   = '<!-- tellora:mirror:end -->'
  BLOCK_PATTERN = /\n?#{Regexp.escape(START_MARK)}.*?#{Regexp.escape(END_MARK)}\n?/m

  # Spree's own layout sections are replaced by the owner's header and footer
  HIDE_SPREE = '.section-header,.section-footer,.section-announcement-bar,.section-newsletter,#footer,' \
               'header[data-controller~="header"]{display:none!important}'

  # Spree's base styles (Tailwind) must not change the owner's design: inside .tm-root
  # everything starts from the browser defaults, exactly like when the design was checked.
  # The design is measured on a screenshot of one width (e.g. 1920px). On desktops it is scaled
  # with the window (px -> vw), so it keeps exactly the same proportions on every screen size.
  MOBILE_MAX = 768

  RESET = '.tm-root{all:revert;display:block;font:initial;color:initial;line-height:normal;letter-spacing:normal;' \
          'word-spacing:normal;text-align:start;text-transform:none}' \
          '.tm-root *:where(:not(svg, svg *)){all:revert}'

  class << self
    # Install a design in a store. Call inside the store's tenant, after its theme is applied.
    def install!(store, theme, design)
      paths = save_images(theme, design['images'])
      swap = ->(text) { text.to_s.gsub(/tellora-image:([a-zA-Z0-9_-]+)/) { paths[Regexp.last_match(1)].to_s } }

      header = clean_html(swap.call(design['header_html']))
      footer = clean_html(swap.call(design['footer_html']))
      main = clean_html(swap.call(design['main_html']))
      css = scale_css(clean_css(swap.call(design['css'])), design['viewport'].to_i)
      background = design['page_bg'].to_s.match?(/\A#\h{6}\z/) ? design['page_bg'] : '#ffffff'

      sale_label = Array(design['products']).filter_map { |p| p['sale_label'].presence if p.is_a?(Hash) }.first.to_s
      save_preferences(theme, 'main_html' => main, 'sale_label' => sale_label,
                              'score' => design['score'].to_f, 'viewport' => design['viewport'].to_i)

      StyleFamily.remove!(store)
      store.update_columns(
        storefront_custom_code_head: merge(store.storefront_custom_code_head,
                                           head_code(design['fonts'], css, background), first: true),
        storefront_custom_code_body_start: merge(store.storefront_custom_code_body_start,
                                                 %(<div class="tm-root tm-header">#{header}</div>), first: true),
        storefront_custom_code_body_end: merge(store.storefront_custom_code_body_end,
                                               %(<div class="tm-root tm-footer">#{footer}</div>), first: false),
        updated_at: Time.current
      )
      store.touch
    end

    # The design saved on a theme, or nil
    def for(theme)
      mirror = theme&.preferences.to_h['mirror'] || theme&.preferences.to_h[:mirror]
      mirror.is_a?(Hash) && mirror['main_html'].present? ? mirror : nil
    end

    # The home page content with the product grid filled with real products.
    # products: [{ name:, price:, compare_price:, image:, url: }]
    def render_main(mirror, products)
      sale_label = mirror['sale_label'].to_s
      html = mirror['main_html'].to_s
      html.sub(%r{(<div[^>]*data-tellora-products="(\d*)"[^>]*>)(.*?<template\s+data-tellora-card[^>]*>(.*?)</template>.*?)</div>}m) do
        opening = Regexp.last_match(1)
        count = Regexp.last_match(2).to_i
        inner = Regexp.last_match(3)
        card = Regexp.last_match(4)
        template = inner[%r{<template\s+data-tellora-card[^>]*>.*?</template>}m]
        cards = products.first([count, 1].max).map do |product|
          on_sale = product[:compare_price].present?
          values = product.merge(sale_label: on_sale ? sale_label.presence || 'Sale' : '')
          card.gsub(/\{\{(name|price|compare_price|sale_label|image|url)\}\}/) { ERB::Util.html_escape(values[Regexp.last_match(1).to_sym].to_s) }
        end
        "#{opening}#{inner.sub(template, cards.join)}</div>"
      end
    end

    private

    def save_images(theme, images)
      return {} unless images.is_a?(Hash)

      helpers = Rails.application.routes.url_helpers
      images.each_with_object({}) do |(id, image), paths|
        next unless id.to_s.match?(/\A[a-zA-Z0-9_-]{1,40}\z/) && image.is_a?(Hash)

        content_type = %w[image/png image/jpeg].include?(image['content_type']) ? image['content_type'] : 'image/jpeg'
        record = theme.theme_images.find_or_initialize_by(section: "mirror_#{id}")
        record.source_url = "screenshot:#{id}" # ThemeImage requires a source; this one is the owner's screenshot
        record.source_attribution = 'From the store owner\'s screenshot'
        record.save!
        record.image.attach(io: StringIO.new(Base64.decode64(image['data'].to_s)),
                            filename: "#{id}.#{content_type == 'image/png' ? 'png' : 'jpg'}",
                            content_type: content_type)
        paths[id.to_s] = helpers.rails_blob_path(record.image, only_path: true)
      rescue StandardError => e
        Rails.logger.warn("[MirrorDesign] image #{id} not saved: #{e.class} - #{e.message}")
      end
    end

    def head_code(fonts, css, background)
      families = Array(fonts).select { |f| f.to_s.match?(/\A[A-Za-z0-9 ]{2,40}\z/) }.first(4)
      font_link =
        if families.any?
          query = families.map { |f| "family=#{f.tr(' ', '+')}:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400" }.join('&')
          %(<link rel="stylesheet" href="https://fonts.googleapis.com/css2?#{query}&display=swap">)
        end
      [
        %(<link rel="preconnect" href="https://fonts.googleapis.com">),
        %(<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>),
        font_link,
        "<style>body{background:#{background}!important;overflow-x:hidden}#{HIDE_SPREE}#{RESET}#{css}</style>"
      ].compact.join("\n")
    end

    # Put a mirror block into one of the store's custom code fields, keeping the owner's own code
    def merge(existing, block, first:)
      own = existing.to_s.gsub(BLOCK_PATTERN, "\n").strip.presence
      wrapped = [START_MARK, block, END_MARK].join("\n")
      (first ? [wrapped, own] : [own, wrapped]).compact.join("\n")
    end

    def save_preferences(theme, values)
      prefs = (theme.preferences || {}).to_h.reject { |k, _| k.to_s == 'mirror' }
      plain = values.transform_keys { |k| String.new(k) }.transform_values { |v| v.is_a?(String) ? String.new(v) : v }
      theme.update_column(:preferences, prefs.merge('mirror' => plain))
    end

    # The design comes from an AI: no scripts, frames, forms or event handlers, ever
    def clean_html(html)
      html = html.gsub(%r{<(script|iframe|object|embed|style|noscript)\b[^>]*>.*?</\1\s*>}mi, '')
      html = html.gsub(%r{</?(script|iframe|object|embed|style|base|meta|link|noscript)\b[^>]*>}i, '')
      html = html.gsub(/\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/i, '')
      html = html.gsub(/javascript:/i, '')
      html.gsub(%r{<(/?)form\b}i, '<\1div').strip
    end

    # Desktop rules: every size in vw of the screenshot width (exact at that width, proportional on
    # others). Phones (<= 768px) keep the original pixel rules and their own @media rules.
    def scale_css(css, viewport)
      return css if viewport < 320

      desktop, mobile = split_mobile(css)
      scaled = desktop.gsub(/(-?\d*\.?\d+)px\b/) do
        value = Regexp.last_match(1).to_f
        value.abs <= 2 ? Regexp.last_match(0) : "#{(value / viewport * 100).round(4)}vw"
      end
      "@media (min-width:#{MOBILE_MAX + 1}px){#{scaled}}@media (max-width:#{MOBILE_MAX}px){#{desktop}}#{mobile}"
    end

    # Splits CSS into [rules for all screens, @media (max-width ...) blocks written for phones]
    def split_mobile(css)
      desktop = +''
      mobile = +''
      index = 0
      while index < css.length
        start = css.index(/@media[^{]*max-width/i, index)
        unless start
          desktop << css[index..]
          break
        end
        desktop << css[index...start]
        open = css.index('{', start)
        break desktop << css[start..] unless open

        depth = 0
        finish = open
        css[open..].each_char.with_index(open) do |char, at|
          depth += 1 if char == '{'
          depth -= 1 if char == '}'
          if depth.zero?
            finish = at
            break
          end
        end
        mobile << css[start..finish]
        index = finish + 1
      end
      [desktop, mobile]
    end

    def clean_css(css)
      css.gsub(/@import[^;]*;/i, '').gsub(/expression\s*\(/i, '').gsub(%r{</style}i, '').strip
    end
  end
end