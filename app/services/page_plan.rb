# frozen_string_literal: true

# The home page plan of a Tellora store: which style family it uses, the words for
# each designer-made section, and the photos for them.
#
# The AI (GenAI Theme API, POST /api/v1/page-plan) only writes words and photo
# searches. This class checks every field, fills anything missing with good
# defaults, downloads the photos into the theme, and installs the family.
#
# Stored in the theme's preferences:
#   'style_family' => 'warm_artisan'
#   'page_plan'    => { 'hero' => {...}, 'promises' => [...], ... }
#   'brand'        => { 'accent' => '#8e2a22', 'display' => {...}, 'body' => {...} }
#                     (only for stores moved from another platform: their own colour and fonts)
# Photos are ThemeImage records with sections plan_hero, plan_story, plan_banner.
class PagePlan
  REQUEST_TIMEOUT = 150 # seconds
  IMAGE_SLOTS = %w[hero story banner].freeze
  ICONS = %w[leaf truck calendar pin shield gift star return heart sparkle hand clock].freeze

  LIMITS = {
    short: 60,   # buttons, kickers, labels
    title: 90,   # headings
    text: 320,   # paragraphs
    query: 60    # photo searches
  }.freeze

  class << self
    # Build and save the plan for a freshly applied theme. Never raises: a store
    # always ends up with a complete plan and its family installed.
    #
    # imported: what Tellora read from the owner's existing store ("Move my store"):
    #   { 'plan' => {...}, 'images' => {...}, 'brand' => {...} }
    def apply!(theme:, store:, description:, previous_theme: nil, imported: nil)
      if reuse_from(previous_theme, theme)
        StyleFamily.install!(store, family_of(theme), brand: brand_of(theme))
        return read(theme)
      end

      return apply_imported!(theme, store, imported) if imported.is_a?(Hash) && imported['plan'].is_a?(Hash)

      raw = begin
        request(store_name: store.name, description: description, currency: store.default_currency)
      rescue StandardError => e
        Rails.logger.warn("[PagePlan] AI plan not available (#{e.class}: #{e.message}), using defaults")
        {}
      end

      plan = normalize(raw, store_name: store.name)
      family = StyleFamily.resolve(raw['family'])
      save(theme, family, plan)
      attach_images(theme, raw['images'])
      StyleFamily.install!(store, family)
      plan
    end

    # The plan of a theme, always complete (old or partial plans get defaults)
    def read(theme)
      stored = preference(theme, 'page_plan')
      normalize(stored.is_a?(Hash) ? stored : {}, store_name: theme.store&.name)
    end

    def family_of(theme)
      key = preference(theme, 'style_family')
      StyleFamily.known?(key) ? key.to_s : nil
    end

    # The store's own colour and fonts (moved stores only), or {}
    def brand_of(theme)
      StyleFamily.clean_brand(preference(theme, 'brand'))
    end

    # Switch a store to another style family. Words, products, photos and brand stay the same.
    def switch_family!(theme:, store:, family:)
      raise ArgumentError, "Unknown style: #{family}" unless StyleFamily.known?(family)

      plan = preference(theme, 'page_plan')
      brand = brand_of(theme)
      save(theme, family.to_s, plan.is_a?(Hash) ? plan : normalize({}, store_name: store.name), brand)
      StyleFamily.install!(store, family.to_s, brand: brand)
    end

    # Photo for a section: ThemeImage or nil
    def image(theme, slot)
      theme.theme_images.find_by(section: "plan_#{slot}")
    end

    # ---- AI request ------------------------------------------------------------

    def request(store_name:, description:, currency:)
      url = "#{ENV.fetch('GENAI_SERVICE_URL', 'http://localhost:8000')}/api/v1/page-plan"
      response = HTTParty.post(
        url,
        body: {
          store_name: store_name.to_s,
          description: description.to_s.truncate(1000),
          currency: currency.presence || 'USD',
          families: StyleFamily.catalogue
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: REQUEST_TIMEOUT
      )
      raise "page-plan API error #{response.code}: #{response.body.to_s.truncate(300)}" unless response.success?

      data = response.parsed_response
      raise 'page-plan API returned no plan' unless data.is_a?(Hash) && data['plan'].is_a?(Hash)

      data['plan'].merge('images' => data['images'].is_a?(Hash) ? data['images'] : {})
    end

    # ---- validation --------------------------------------------------------------

    def normalize(raw, store_name:)
      raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      base = defaults(store_name)

      hero = hash(raw['hero'])
      story = hash(raw['story'])
      steps = hash(raw['steps'])
      banner = hash(raw['banner'])
      products = hash(raw['products'])

      {
        'hero' => {
          'kicker' => text(hero['kicker'], :short, base['hero']['kicker']),
          'title' => text(hero['title'], :title, base['hero']['title']),
          'emphasis' => text(hero['emphasis'], :short, hero['title'].present? ? '' : base['hero']['emphasis']),
          'lede' => text(hero['lede'], :text, base['hero']['lede']),
          'primary_cta' => text(hero['primary_cta'], :short, base['hero']['primary_cta']),
          'secondary_cta' => text(hero['secondary_cta'], :short, base['hero']['secondary_cta']),
          'note_title' => text(hero['note_title'], :short, base['hero']['note_title']),
          'note_text' => text(hero['note_text'], :text, base['hero']['note_text']),
          'image_query' => text(hero['image_query'], :query, '')
        },
        'promises' => promises(raw['promises'], base['promises']),
        'products' => {
          'title' => text(products['title'], :title, base['products']['title']),
          'subtitle' => text(products['subtitle'], :text, base['products']['subtitle']),
          'link_label' => text(products['link_label'], :short, base['products']['link_label']),
          'card_cta' => text(products['card_cta'], :short, base['products']['card_cta'])
        },
        'story' => {
          'title' => text(story['title'], :title, base['story']['title']),
          'paragraphs' => paragraphs(story['paragraphs'], base['story']['paragraphs']),
          'signature' => text(story['signature'], :short, base['story']['signature']),
          'image_query' => text(story['image_query'], :query, '')
        },
        'steps' => {
          'title' => text(steps['title'], :title, base['steps']['title']),
          'items' => step_items(steps['items'], base['steps']['items'])
        },
        'banner' => {
          'title' => text(banner['title'], :title, base['banner']['title']),
          'text' => text(banner['text'], :text, base['banner']['text']),
          'cta' => text(banner['cta'], :short, base['banner']['cta']),
          'image_query' => text(banner['image_query'], :query, '')
        }
      }
    end

    # Copy used when the AI is unavailable: written to work for any shop
    def defaults(store_name)
      name = store_name.to_s.strip.presence || 'our shop'
      {
        'hero' => {
          'kicker' => name.truncate(LIMITS[:short]),
          'title' => 'Made with care,',
          'emphasis' => 'chosen for you.',
          'lede' => 'A small collection of things we love and use ourselves, sent to you with the same care we put into choosing them.',
          'primary_cta' => 'Shop the collection',
          'secondary_cta' => 'Our story',
          'note_title' => 'New this week',
          'note_text' => 'Fresh arrivals, in limited numbers. Take a look before they go.'
        },
        'promises' => [
          { 'icon' => 'heart', 'title' => 'Chosen with care', 'text' => 'Every item is picked and checked by us.' },
          { 'icon' => 'truck', 'title' => 'Fast delivery', 'text' => 'Packed carefully and sent out quickly.' },
          { 'icon' => 'return', 'title' => 'Easy returns', 'text' => 'Not right for you? Send it back, no fuss.' }
        ],
        'products' => {
          'title' => 'Our favourites',
          'subtitle' => 'The pieces our customers come back for, again and again.',
          'link_label' => 'Shop all',
          'card_cta' => 'View product'
        },
        'story' => {
          'title' => "Why we started #{name}".truncate(LIMITS[:title]),
          'paragraphs' => [
            'We wanted a shop that only sells what we would happily buy ourselves. So we keep the range small, get to know the people who make it, and test everything before it goes on sale.',
            'It takes longer that way. It is also why our customers trust what arrives at their door.'
          ],
          'signature' => "The #{name} team".truncate(LIMITS[:short])
        },
        'steps' => {
          'title' => 'How it works',
          'items' => [
            { 'title' => 'Choose', 'text' => 'Browse the collection and pick what you love.' },
            { 'title' => 'We pack it', 'text' => 'Every order is checked and packed by hand.' },
            { 'title' => 'We send it', 'text' => 'Tracked delivery, with updates along the way.' },
            { 'title' => 'Enjoy it', 'text' => 'And tell us what you think. We read every message.' }
          ]
        },
        'banner' => {
          'title' => 'Something new, every season.',
          'text' => 'Sign up to our newsletter below and be the first to see new arrivals and special offers.',
          'cta' => 'See what is new'
        }
      }
    end

    private

    # "Move my store": the plan written from the owner's own site, their photos,
    # and their colour and fonts on top of the chosen family
    def apply_imported!(theme, store, imported)
      raw = imported['plan'].deep_stringify_keys
      plan = normalize(raw, store_name: store.name)
      family = StyleFamily.resolve(raw['family'])
      brand = StyleFamily.clean_brand(imported['brand'])
      save(theme, family, plan, brand)
      attach_images(theme, imported['images'])
      StyleFamily.install!(store, family, brand: brand)
      plan
    rescue StandardError => e
      Rails.logger.warn("[PagePlan] imported plan failed (#{e.class}: #{e.message}), using defaults")
      plan = normalize({}, store_name: store.name)
      save(theme, StyleFamily::DEFAULT, plan)
      StyleFamily.install!(store, StyleFamily::DEFAULT)
      plan
    end

    # When the builder applies a refined design, keep the plan and photos of the
    # design it replaces (words and photos only change when asked).
    def reuse_from(previous_theme, theme)
      return false unless previous_theme && previous_theme.id != theme.id

      family = family_of(previous_theme)
      stored = preference(previous_theme, 'page_plan')
      return false unless family && stored.is_a?(Hash)

      save(theme, family, stored, brand_of(previous_theme))
      IMAGE_SLOTS.each do |slot|
        old = image(previous_theme, slot)
        next unless old&.image&.attached?

        copy = theme.theme_images.create!(
          section: "plan_#{slot}",
          source_url: old.source_url,
          source_attribution: old.source_attribution,
          metadata: old.metadata
        )
        copy.image.attach(old.image.blob)
      end
      true
    rescue StandardError => e
      Rails.logger.warn("[PagePlan] could not reuse previous plan: #{e.class} - #{e.message}")
      false
    end

    # Theme preferences are stored as YAML that only accepts plain Ruby types,
    # so the plan is converted to plain strings, arrays and hashes first.
    def save(theme, family, plan, brand = {})
      prefs = (theme.preferences || {}).to_h
      prefs = prefs.reject { |k, _| %w[style_family page_plan brand].include?(k.to_s) }
      values = { 'style_family' => family.to_s.dup, 'page_plan' => plain(plan) }
      values['brand'] = plain(brand) if brand.present?
      theme.update_column(:preferences, prefs.merge(values))
    end

    def plain(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), out| out[String.new(k.to_s)] = plain(v) }
      when Array then value.map { |v| plain(v) }
      when String then String.new(value.to_str)
      when Numeric, true, false, nil then value
      else String.new(value.to_s)
      end
    end

    def attach_images(theme, images)
      return unless images.is_a?(Hash)

      manager = ThemeImageManager.new(theme)
      IMAGE_SLOTS.each do |slot|
        info = images[slot]
        url = info.is_a?(Hash) ? info['url'].to_s : ''
        next unless url.start_with?('https://')

        manager.replace_image("plan_#{slot}", url, info.slice('user', 'page_url', 'query'))
      end
    rescue StandardError => e
      Rails.logger.warn("[PagePlan] photos not attached: #{e.class} - #{e.message}")
    end

    def preference(theme, key)
      prefs = theme&.preferences || {}
      prefs[key] || prefs[key.to_sym]
    end

    def hash(value)
      value.is_a?(Hash) ? value : {}
    end

    def text(value, limit, fallback)
      clean = String.new(ActionController::Base.helpers.strip_tags(value.to_s).to_str).squish
      clean = clean.truncate(LIMITS.fetch(limit), separator: ' ', omission: '…') if clean.length > LIMITS.fetch(limit)
      clean.presence || fallback.to_s
    end

    def promises(value, fallback)
      items = Array(value).select { |i| i.is_a?(Hash) }.first(3).map do |item|
        {
          'icon' => ICONS.include?(item['icon'].to_s) ? item['icon'].to_s : 'sparkle',
          'title' => text(item['title'], :short, ''),
          'text' => text(item['text'], :text, '')
        }
      end
      items = items.reject { |i| i['title'].blank? }
      items.size == 3 ? items : fallback
    end

    def paragraphs(value, fallback)
      items = Array(value).map { |p| text(p, :text, '') }.reject(&:blank?).first(2)
      items.any? ? items : fallback
    end

    def step_items(value, fallback)
      items = Array(value).select { |i| i.is_a?(Hash) }.first(4).map do |item|
        { 'title' => text(item['title'], :short, ''), 'text' => text(item['text'], :text, '') }
      end
      items = items.reject { |i| i['title'].blank? }
      items.size >= 3 ? items : fallback
    end
  end
end