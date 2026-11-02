require 'roo'
class ProductNotCreatedError < ::StandardError
end

class ProductsImport::Import
  attr_accessor :imported_sheet, :spree_current_user

  def initialize(file_path, spree_current_user, import_log, current_store)
    Rails.logger.info "=== IMPORT INITIALIZATION ==="
    Rails.logger.info "File path: #{file_path}"
    Rails.logger.info "User: #{spree_current_user&.email}"
    Rails.logger.info "Store: #{current_store&.name}"
    Rails.logger.info "Store ID: #{current_store&.id} (#{current_store&.id&.class})"
    
    @import_log = import_log
    @spree_current_user = spree_current_user
    @current_store = current_store
    
    begin
      Rails.logger.info "Opening Excel file..."
      imported_file = Roo::Spreadsheet.open(file_path, extension: :xlsx)
      @imported_sheet = imported_file.sheet(0)
      Rails.logger.info "Excel file opened successfully. Rows: #{@imported_sheet.last_row}"
    rescue => e
      Rails.logger.error "Failed to open Excel file: #{e.message}"
      raise e
    end
    
    begin
      Rails.logger.info "Setting up taxonomy and country..."
      @taxonomy = Spree::Taxonomy.where(name: 'Categories', store: @current_store).first_or_create!
      @country = Spree::Country.find_by(iso: 'US')
      Rails.logger.info "Taxonomy: #{@taxonomy.name}, Country: #{@country&.name}"
    rescue => e
      Rails.logger.error "Failed to setup taxonomy/country: #{e.message}"
      raise e
    end
    
    Rails.logger.info "=== INITIALIZATION COMPLETE ==="
  end

  def perform_import
    Rails.logger.info "=== STARTING IMPORT PROCESS ==="
    @failed = []
    @processed_skus = []
    
    begin
      @import_log.update_columns(state: 'running')
      Rails.logger.info "Import log state updated to 'running'"
    rescue => e
      Rails.logger.error "Failed to update import log: #{e.message}"
    end
    
    header = imported_sheet.row(1)
    Rails.logger.info "Headers: #{header}"
    
    total_rows = imported_sheet.last_row - 1
    Rails.logger.info "Processing #{total_rows} product rows..."
    
    (2..imported_sheet.last_row).each do |index|
      Rails.logger.info "--- Processing row #{index}/#{imported_sheet.last_row} ---"
      row = [header, imported_sheet.row(index)].transpose.to_h
      
      if row['SKU'].blank? && row['Name'].blank?
        Rails.logger.info "Skipping empty row #{index}"
        next
      end
      
      Rails.logger.info "Row data: SKU='#{row['SKU']}', Name='#{row['Name']}'"
      
      begin
        create_product(row, index)
        Rails.logger.info "Row #{index} processed successfully"
      rescue => e
        Rails.logger.error "Row #{index} failed: #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(3).join("\n")}"
      end
    end
    
    begin
      @import_log.update_column(:state, 'finished')
      Rails.logger.info "Import completed. State updated to 'finished'"
    rescue => e
      Rails.logger.error "Failed to update final import log: #{e.message}"
    end
    
    Rails.logger.info "=== IMPORT PROCESS COMPLETE ==="
  end

  private

  def create_product(row, index)
    @failed ||= []
    return if row['SKU'].blank? && row['Name'].blank?
    
    Rails.logger.info "Creating product: #{row['Name']}"
    
    begin
      shipping_category = find_or_create_shipping_category(row['ShippingCategory']) if row['ShippingCategory']
      Rails.logger.info "Shipping category: #{shipping_category&.name}"
    rescue => e
      Rails.logger.error "Shipping category error: #{e.message}"
      raise e
    end
    
    begin
      tax_category = find_or_create_tax_category(row['TaxCategory']) if row['TaxCategory']
      Rails.logger.info "Tax category: #{tax_category&.name}"
    rescue => e
      Rails.logger.error "Tax category error: #{e.message}"
      raise e
    end
    
    original_sku = row['SKU'].to_s.strip
    unique_sku = generate_unique_sku(original_sku)
    @processed_skus << unique_sku
    Rails.logger.info "SKU: #{original_sku} -> #{unique_sku}"
    
    begin
      Rails.logger.info "Creating product object..."
      @product = Spree::Product.new(
        name: row['Name'], 
        price: row['Price'],
        shipping_category: shipping_category, 
        description: row['Description'],
        available_on: row['AvailableOn'].present? ? Time.parse(row['AvailableOn'].to_s) : Time.current,
        meta_description: row['SEO Description'],
        meta_title: row['SEO Title'],
        status: 'active'
      )
      Rails.logger.info "Product object created"
      
      @product.stores << @current_store
      @product.tax_category = tax_category
      @product.sku = unique_sku
      @product.cost_price = row['CostPrice']
      @product.master.currency = @current_store.default_currency
      @product.master.cost_currency = @current_store.default_currency
      @product.master.cost_price = row['CostPrice']
      
      Rails.logger.info "Product attributes set, attempting save..."
      
      if @product.save!
        Rails.logger.info "Product saved successfully with ID: #{@product.id}"
        
        # ALWAYS set stock regardless of variants
        if row['CountOnHand'].present?
          Rails.logger.info "Setting stock: #{row['CountOnHand']}"
          set_stock(@product.master, row['CountOnHand'])
        end
        
        # Handle variants if present
        if row['Variants'].present?
          Rails.logger.info "Processing variants..."
          save_variants(@product, row)
        end
        
        # Handle images
        if row['Image'].present?
          Rails.logger.info "Processing images..."
          save_images(@product.master, row['Image'])
        end
        
        save_properties(row) if row['ProductProperties']
        save_taxons(row, @product) if row['Taxons']
        
        @import_log.increment!(:success_row_count)
        Rails.logger.info "Product creation completed successfully"
      else
        Rails.logger.error "Product save failed: #{@product.errors.full_messages.join(', ')}"
        raise ProductNotCreatedError.new("Product validation failed: #{@product.errors.full_messages.join(', ')}")
      end
    rescue => e
      Rails.logger.error "Product creation failed: #{e.message}"
      Rails.logger.error "Product errors: #{@product&.errors&.full_messages&.join(', ')}" if @product
      raise e
    end
  rescue => e
    Rails.logger.error "Error in create_product: #{e.message}"
    handle_exception(row, e, index)
  end

  def set_stock(variant, quantity)
    Rails.logger.info "Setting stock for variant #{variant.sku}: #{quantity}"
    
    stock_location = Spree::StockLocation.where(default: true).first_or_create!(
      name: 'Default', 
      default: true, 
      address1: 'Example Street',
      city: 'City', 
      zipcode: '12345', 
      country: @country, 
      state: @country.states.first,
      active: true, 
      propagate_all_variants: true
    )
    
    stock_item = stock_location.set_up_stock_item(variant)
    stock_item.update!(count_on_hand: quantity.to_i, backorderable: true)
    variant.update!(track_inventory: true)
    Rails.logger.info "Stock set: #{quantity} for #{variant.sku}"
  end

  def save_images(variant, image_urls)
    return if image_urls.blank?
    
    Rails.logger.info "Processing images for variant #{variant.sku}"
    
    image_urls.to_s.split('|').each do |img_url|
      next if img_url.blank?
      
      begin
        filename = "#{variant.sku}_#{Time.current.to_i}.jpg"
        Rails.logger.info "Downloading image: #{img_url}"
        image = URI.parse(img_url.strip).open(read_timeout: 5)
        variant.images.create!(attachment: { io: image, filename: filename })
        Rails.logger.info "Image saved: #{filename}"
      rescue => e
        Rails.logger.error "Image failed for #{img_url}: #{e.message}"
      end
    end
  end

  def save_variants(product, row)
    Rails.logger.info "Processing variants for product #{product.name}"
    
    variants_data = row['Variants'].to_s.split('|')
    quantities = row['CountOnHand']&.to_s&.split('|') || []
    
    variants_data.each_with_index do |variant_options, index|
      Rails.logger.info "Processing variant #{index + 1}: #{variant_options}"
      
      option_values = []
      variant_options.split(';').each do |v|
        option_type_and_value = v.strip.split(':')
        next if option_type_and_value.size != 2
        
        option_type = Spree::OptionType.find_by(name: option_type_and_value.first)
        next unless option_type
        
        unless product.option_types.include?(option_type)
          product.option_types << option_type
        end
        
        option_value = option_type.option_values.find_by(name: option_type_and_value.second)
        option_values << option_value if option_value
      end
      
      next if option_values.empty?

      variant_sku = "#{product.master.sku}_#{option_values.map(&:name).join('_')}"
      quantity = quantities[index] || quantities.first || 0
      
      Rails.logger.info "Creating variant with SKU: #{variant_sku}"
      
      new_variant = product.variants.create!(
        cost_price: product.cost_price || 0,
        sku: variant_sku,
        cost_currency: @current_store.default_currency,
        currency: @current_store.default_currency,
        track_inventory: true,
        option_values: option_values
      )
      
      set_stock(new_variant, quantity)
      
      if row['Image'].present?
        save_images(new_variant, row['Image'])
      end
    end
    
    product.save!
  end

  def error_details(row, e, index)
    {"row_#{index}": { product_name: row['Name'], message: e.message }}
  end

  def handle_exception(product, e, index)
    Rails.logger.error "Handling exception for row #{index}: #{e.message}"
    @failed.push(product['Name'])
    data = error_details(product, e, index)
    
    begin
      @import_log.error_details ||= {}
      @import_log.error_details.merge!(data)
      @import_log.increment!(:error_row_count)
      @import_log.save
    rescue => log_error
      Rails.logger.error "Failed to update error log: #{log_error.message}"
    end
  end

  def save_taxons(row, product)
    return unless row['Taxons'].present?
    
    Rails.logger.info "Processing taxons: #{row['Taxons']}"
    
    categories_taxon = @taxonomy.taxons.where(name: I18n.t('spree.taxonomy_categories_name')).first_or_create!

    row['Taxons'].to_s.split('|').each do |taxon|
      if taxon.split('>').size == 1
        parent = categories_taxon.children.where(name: taxon).first_or_create!
        product.taxons << parent unless product.taxons.find_by(name: parent.name)
      else
        final_taxons = nil
        taxon.split('>').each do |t|
          categories_taxon = categories_taxon.children.where(name: t).first_or_create!
          final_taxons = categories_taxon
        end
        product.taxons << final_taxons unless product.taxons.find_by(name: final_taxons.name)
      end
    end
    product.save
  end

  def find_or_create_shipping_category(name)
    Rails.logger.info "Finding/creating shipping category: #{name}"
    result = Spree::ShippingCategory.find_or_create_by(name: name)
    Rails.logger.info "Shipping category result: #{result.name}"
    result
  end

  def find_or_create_tax_category(name)
    Rails.logger.info "Finding/creating tax category: #{name}"
    Rails.logger.info "Store ID: #{@current_store.id} (#{@current_store.id.class})"
    
    # FIX: Use string interpolation instead of concatenation
    category_name = "#{name}_#{@current_store.id}"
    Rails.logger.info "Full tax category name: #{category_name}"
    
    result = Spree::TaxCategory.find_or_create_by(name: category_name)
    Rails.logger.info "Tax category result: #{result.name}"
    result
  end

  def save_properties(row)
    return unless row['ProductProperties'].present?
    
    Rails.logger.info "Processing properties: #{row['ProductProperties']}"
    
    properties = row['ProductProperties'].to_s.split('|')
    properties.each do |p|
      final_property = p.split(':')
      next if final_property.size != 2
      
      property = Spree::Property.find_or_create_by(name: final_property[0], presentation: final_property[0])
      product_property = Spree::ProductProperty.where(product: @product, property: property).first_or_initialize
      product_property.value = final_property[1]
      product_property.save
    end
  end

  def generate_unique_sku(original_sku)
    return SecureRandom.alphanumeric(10).upcase if original_sku.blank?
    
    return original_sku unless @processed_skus.include?(original_sku) || Spree::Variant.exists?(sku: original_sku)
    
    counter = 1
    loop do
      new_sku = "#{original_sku}_#{counter}"
      return new_sku unless @processed_skus.include?(new_sku) || Spree::Variant.exists?(sku: new_sku)
      counter += 1
      return "#{original_sku}_#{SecureRandom.alphanumeric(6).upcase}" if counter > 100
    end
  end
end