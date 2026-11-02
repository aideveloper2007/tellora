# frozen_string_literal: true

require 'open-uri'

# Creates AI-generated sample products for a newly themed store so it doesn't start empty.
#
# - Asks the GenAI Theme API (Claude + Pixabay) for products matching the store type
# - Creates real Spree products (price, category, stock, image) in the CURRENT Apartment tenant
# - Marks them with private_metadata { sample: true } so they can be removed later
# - Does nothing if the store already has products
class SampleProductsGenerator
  DEFAULT_COUNT = 8
  STOCK_PER_PRODUCT = 50
  REQUEST_TIMEOUT = 180 # seconds; Claude can take a while for 8+ products

  def initialize(store:, store_type:, count: DEFAULT_COUNT)
    @store = store
    @store_type = store_type.to_s.presence || 'general'
    @count = count
  end

  # Returns the number of products created
  def call
    unless @store
      log 'No store found, skipping sample products'
      return 0
    end

    if @store.products.exists?
      log "Store #{@store.code} already has products, skipping sample products"
      return 0
    end

    items = fetch_products
    log "Received #{items.size} sample products for '#{@store_type}'"

    created = 0
    items.each do |item|
      created += 1 if create_product(item)
    end

    log "Created #{created} sample products in store #{@store.code}"
    created
  end

  private

  def fetch_products
    url = "#{ENV.fetch('GENAI_SERVICE_URL', 'http://localhost:8000')}/api/v1/sample-products"
    response = HTTParty.post(
      url,
      body: {
        store_type: @store_type,
        store_name: @store.name,
        count: @count,
        currency: @store.default_currency.presence || 'USD'
      }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: REQUEST_TIMEOUT
    )

    raise "Sample products API error #{response.code}: #{response.body.to_s.truncate(500)}" unless response.success?

    Array(response.parsed_response['products'])
  end

  def create_product(item)
    price = BigDecimal(item['price'].to_s)
    return false if item['name'].blank? || price <= 0

    product = nil
    Spree::Product.transaction do
      product = Spree::Product.new(
        name: item['name'].to_s.truncate(200),
        description: item['description'].to_s,
        shipping_category: shipping_category,
        status: 'active',
        available_on: Time.current,
        stores: [@store]
      )
      # Spree 5.1: price lives on the master variant's default price (store default currency)
      product.master.price = price
      product.master.currency = @store.default_currency.presence || 'USD'
      product.private_metadata = { 'sample' => true, 'source' => 'genai' } if product.respond_to?(:private_metadata=)
      product.taxons << category_taxon(item['category'])
      product.save!

      set_stock(product.master)
    end

    attach_image(product.master, item['image_url'], product.name)
    true
  rescue StandardError => e
    log "Failed to create sample product '#{item['name']}': #{e.class} - #{e.message}"
    false
  end

  def set_stock(variant)
    if Spree::StockLocation.exists?
      variant.stock_items.each { |stock_item| stock_item.set_count_on_hand(STOCK_PER_PRODUCT) }
    else
      # No stock location set up yet: keep samples purchasable
      variant.update!(track_inventory: false)
    end
  end

  def attach_image(variant, url, alt)
    return if url.blank?

    uri = URI.parse(url)
    return unless uri.is_a?(URI::HTTPS)

    io = uri.open(open_timeout: 10, read_timeout: 30)
    filename = File.basename(uri.path).presence || 'product.jpg'
    variant.images.create!(
      attachment: { io: io, filename: filename, content_type: io.content_type },
      alt: alt
    )
  rescue StandardError => e
    log "Image download failed for '#{alt}': #{e.message}"
  end

  def shipping_category
    @shipping_category ||= Spree::ShippingCategory.first || Spree::ShippingCategory.create!(name: 'Default')
  end

  def categories_taxonomy
    @categories_taxonomy ||= @store.taxonomies.find_or_create_by!(name: 'Categories')
  end

  def category_taxon(name)
    name = name.to_s.strip.presence || 'General'
    root = categories_taxonomy.root
    root.children.find_by(name: name) ||
      Spree::Taxon.create!(name: name, parent: root, taxonomy: categories_taxonomy)
  end

  def log(message)
    Rails.logger.info "[SampleProducts] #{message}"
  end
end
