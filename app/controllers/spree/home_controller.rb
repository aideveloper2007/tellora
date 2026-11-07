# frozen_string_literal: true

# Override Spree's HomeController to add GenAI theme support.
#
# Four cases:
#   0. Design rebuilt from the owner's screenshots ("Move my store", MirrorDesign):
#      their own home page, with the product grid filled with this store's products.
#   1. GenAI theme with a style family (all Tellora stores): designer-made sections
#      from the page plan, inside Spree's own layout (header, newsletter, footer).
#   2. Older GenAI theme without a family: the previous GenAI home page, unchanged.
#   3. Any other theme: Spree's default home page.
module Spree
  class HomeController < Spree::StoreController
    include GenaiThemeHelper
    helper 'genai_theme'
    helper TelloraSectionsHelper
    before_action :ensure_theme_images_table, if: -> { using_genai_theme? }

    FAMILY_PRODUCT_LIMIT = 8
    MIRROR_PRODUCT_LIMIT = 24

    def index
      if using_genai_theme? && (mirror = MirrorDesign.for(current_genai_theme))
        @mirror_html = MirrorDesign.render_main(mirror, mirror_products(MIRROR_PRODUCT_LIMIT))
        render 'spree/home/index_mirror'
      elsif using_genai_theme? && (family = PagePlan.family_of(current_genai_theme))
        @style_family = family
        @page_plan = PagePlan.read(current_genai_theme)
        @plan_images = PagePlan::IMAGE_SLOTS.index_with { |slot| PagePlan.image(current_genai_theme, slot) }
        @products = home_products(FAMILY_PRODUCT_LIMIT)
        render 'spree/home/index_family'
      elsif using_genai_theme?
        @products = home_products(genai_product_limit)
        render 'spree/home/index_genai'
      else
        # Spree's default homepage rendering
        render 'spree/home/index'
      end
    rescue ActionView::MissingTemplate
      # Fallback if custom template doesn't exist yet
      render inline: homepage_content
    end

    private

    # Products for a rebuilt design's product grid, as plain values for its card template
    def mirror_products(limit)
      helpers = view_context
      home_products(limit).map do |product|
        {
          name: product.name,
          price: helpers.tl_price(product),
          compare_price: mirror_compare_price(product),
          image: (product.default_image ? helpers.tl_image_url(product.default_image, width: 800, height: 800) : ''),
          url: spree.product_path(product)
        }
      end
    rescue StandardError => e
      Rails.logger.error("[Home] products for the rebuilt design failed: #{e.class} - #{e.message}")
      []
    end

    # "Was" price when the product is on sale, otherwise ''
    def mirror_compare_price(product)
      price = product.price_in(current_currency)
      return '' unless price.respond_to?(:compare_at_amount) && price.compare_at_amount.present? && price.amount.present?
      return '' unless price.compare_at_amount > price.amount

      price.respond_to?(:display_compare_at_price) ? price.display_compare_at_price.to_s : ''
    rescue StandardError
      ''
    end

    # Newest active products of this store that have a price in the current currency
    def home_products(limit)
      current_store.products
                   .active(current_currency)
                   .preload(:taxons, master: [:prices, :images], variants_including_master: [:prices])
                   .reorder(created_at: :desc)
                   .limit(limit)
                   .to_a
    rescue StandardError => e
      Rails.logger.error("[Home] products query failed: #{e.class} - #{e.message}")
      []
    end

    def genai_product_limit
      layout_config = current_genai_theme.layout
      grid_columns = (layout_config['grid_columns'] || 3).to_i
      grid_columns = 3 unless grid_columns.between?(1, 6)
      grid_columns * 2 # Show 2 rows
    end

    def homepage_content
      if using_genai_theme?
        <<~HTML
          <%= render 'shared/genai_promo_banner' %>
          <%= render 'shared/genai_hero' %>
          <%= render 'shared/genai_featured_products', products: @products %>
        HTML
      else
        <<~HTML
          <div class="container mx-auto px-4 py-8">
            <h1 class="text-4xl font-bold mb-4">Welcome to <%= current_store.name %></h1>
            <p>Your store is ready!</p>
          </div>
        HTML
      end
    end

    # Lazy migration: Create theme_images table on-demand
    def ensure_theme_images_table
      return if ActiveRecord::Base.connection.table_exists?('theme_images')

      Rails.logger.info "=== Creating theme_images table for tenant: #{Apartment::Tenant.current} ==="

      ActiveRecord::Migration.suppress_messages do
        ActiveRecord::Base.connection.create_table :theme_images do |t|
          t.references :theme, foreign_key: { to_table: :spree_themes }, null: false
          t.string :section, null: false
          t.string :source_url
          t.string :source_attribution
          t.text :metadata
          t.timestamps
        end

        ActiveRecord::Base.connection.add_index :theme_images, [:theme_id, :section], unique: true
      end

      Rails.logger.info "=== theme_images table created successfully ==="
    rescue => e
      Rails.logger.error "=== ERROR creating theme_images table: #{e.message} ==="
    end
  end
end