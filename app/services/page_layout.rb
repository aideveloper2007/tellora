# frozen_string_literal: true

# The home page of a store with a style family, as an ordered list of sections the
# owner can change from the builder chat ("add a categories section", "show 16
# products", "remove the story", "put the FAQ after the products").
#
# Stored in the theme's preferences as 'page_layout':
#   [{ 'type' => 'hero' }, { 'type' => 'products', 'count' => 12, 'title' => '' }, ...]
#
# Section types (every style family styles all of them):
#   hero, promises, story, steps, banner  words from the page plan (PagePlan), once each
#   products     newest products               title, subtitle, count
#   collection   products of one category      category (permalink), title, subtitle, count
#   categories   the store's categories        title, subtitle, count
#   faq          questions and answers         title, items [{ question, answer }]
#   text         a block of text               title, text
#   reviews      the owner's real reviews      title, items [{ quote, name }]
#
# Stores without a saved list get DEFAULT, which is exactly the page they had before.
class PageLayout
  PLAN_TYPES = %w[hero promises story steps banner].freeze
  TYPES = (PLAN_TYPES + %w[products collection categories faq text reviews]).freeze
  MAX_SECTIONS = 14

  DEFAULT = [
    { 'type' => 'hero' },
    { 'type' => 'promises' },
    { 'type' => 'products', 'count' => 8 },
    { 'type' => 'story' },
    { 'type' => 'steps' },
    { 'type' => 'banner' }
  ].freeze

  COUNTS = {
    'products' => [4, 24, 8],
    'collection' => [4, 24, 8],
    'categories' => [2, 12, 6]
  }.freeze

  LIMITS = { title: 90, subtitle: 200, text: 1500, question: 160, answer: 600, quote: 400, name: 60 }.freeze

  class << self
    # The page's sections, always valid (DEFAULT when nothing was saved)
    def read(theme)
      prefs = theme&.preferences || {}
      raw = prefs['page_layout'] || prefs[:page_layout]
      list = normalize(raw, keep_reviews: true)
      list.presence || DEFAULT.map(&:dup)
    end

    def saved?(theme)
      prefs = theme&.preferences || {}
      (prefs['page_layout'] || prefs[:page_layout]).is_a?(Array)
    end

    def save!(theme, list)
      prefs = (theme.preferences || {}).to_h.reject { |k, _| k.to_s == 'page_layout' }
      theme.update_column(:preferences, prefs.merge('page_layout' => plain(list)))
    end

    # Copies the list to a new theme (a refined design keeps the owner's page)
    def copy!(from_theme, to_theme)
      return unless saved?(from_theme)

      save!(to_theme, read(from_theme))
    end

    # Checks every section the AI (or anyone) sends.
    #   owner_text:   what the owner wrote; reviews are only kept when their quote is in it
    #   previous:     the current list; reviews already on the page are kept
    #   keep_reviews: true when reading what was saved before
    def normalize(raw, owner_text: '', previous: [], keep_reviews: false)
      return [] unless raw.is_a?(Array)

      known_quotes = Array(previous).select { |s| s.is_a?(Hash) && s['type'] == 'reviews' }
                                    .flat_map { |s| Array(s['items']).map { |i| squash(i['quote']) } }
      owner = squash(owner_text)
      seen = []

      raw.first(MAX_SECTIONS * 2).filter_map do |item|
        item = item.to_unsafe_h if item.respond_to?(:to_unsafe_h)
        next unless item.is_a?(Hash)

        item = item.stringify_keys
        type = item['type'].to_s
        next unless TYPES.include?(type)
        next if PLAN_TYPES.include?(type) && seen.include?(type)

        seen << type
        clean(type, item, owner: owner, known_quotes: known_quotes, keep_reviews: keep_reviews)
      end.first(MAX_SECTIONS)
    end

    # Short description of the page for the AI and for logs
    def describe(list)
      list.each_with_index.map do |section, index|
        details = section.except('type').map do |key, value|
          value.is_a?(Array) ? "#{key}: #{value.size} items" : "#{key}: #{value}"
        end
        "#{index + 1}. #{section['type']}#{" (#{details.join(', ')})" if details.any?}"
      end.join("\n")
    end

    # ---- categories ----------------------------------------------------------------

    # The store's categories (taxons below the root of the "Categories" taxonomy, or of any
    # taxonomy when there is none), those with products first.
    def categories(store, limit: 40)
      taxonomy_ids = store.taxonomies.pluck(:id, :name)
      preferred = taxonomy_ids.select { |_, name| name.to_s.casecmp('categories').zero? }.map(&:first)
      ids = preferred.presence || taxonomy_ids.map(&:first)
      return [] if ids.empty?

      taxons = Spree::Taxon.where(taxonomy_id: ids).where.not(parent_id: nil).order(:depth, :lft).limit(200).to_a
      with_products = Spree::Classification.where(taxon_id: taxons.map(&:id)).distinct.pluck(:taxon_id)
      taxons.sort_by { |t| [with_products.include?(t.id) ? 0 : 1, t.depth.to_i, t.lft.to_i] }.first(limit)
    rescue StandardError => e
      Rails.logger.warn("[PageLayout] categories failed: #{e.class} - #{e.message}")
      []
    end

    # One category by permalink (or by name)
    def find_category(store, value)
      key = value.to_s.strip.downcase
      return nil if key.empty?

      categories(store, limit: 200).find do |taxon|
        taxon.permalink.to_s.downcase == key || taxon.name.to_s.downcase == key ||
          taxon.permalink.to_s.downcase.split('/').last == key
      end
    end

    private

    def clean(type, item, owner:, known_quotes:, keep_reviews:)
      section = { 'type' => type }
      case type
      when 'products', 'collection', 'categories'
        min, max, default = COUNTS[type]
        count = item['count'].to_i
        section['count'] = count.positive? ? count.clamp(min, max) : default
        section['title'] = text(item['title'], :title)
        section['subtitle'] = text(item['subtitle'], :subtitle)
        section['category'] = item['category'].to_s.strip.downcase.first(150) if type == 'collection'
      when 'faq'
        section['title'] = text(item['title'], :title)
        section['items'] = Array(item['items']).filter_map do |entry|
          next unless entry.is_a?(Hash)

          question = text(entry['question'], :question)
          answer = text(entry['answer'], :answer)
          { 'question' => question, 'answer' => answer } if question.present? && answer.present?
        end.first(8)
      when 'text'
        section['title'] = text(item['title'], :title)
        section['text'] = text(item['text'], :text, keep_lines: true)
      when 'reviews'
        section['title'] = text(item['title'], :title)
        section['items'] = Array(item['items']).filter_map do |entry|
          next unless entry.is_a?(Hash)

          quote = text(entry['quote'], :quote)
          next if quote.blank?
          # Never invented: the quote must be on the page already or in the owner's own words
          next unless keep_reviews || known_quotes.include?(squash(quote)) || (owner.present? && owner.include?(squash(quote)))

          { 'quote' => quote, 'name' => text(entry['name'], :name) }
        end.first(6)
      end
      section
    end

    def text(value, limit, keep_lines: false)
      clean = ActionController::Base.helpers.strip_tags(value.to_s)
      clean = keep_lines ? clean.gsub(/[ \t]+/, ' ').gsub(/\n{3,}/, "\n\n").strip : clean.squish
      String.new(clean.truncate(LIMITS.fetch(limit), separator: ' ', omission: '…'))
    end

    def squash(value)
      value.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, ' ').squish
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
  end
end
