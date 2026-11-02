# Save as: lib/tasks/import_orders.rake
# Run on NEW server

require 'csv'

namespace :spree do
  desc "Import orders from CSV for specific tenant"
  task import_orders: :environment do
    
    # Get parameters
    tenant_name = ENV['TENANT'] || ENV['tenant']
    csv_file = ENV['CSV'] || ENV['csv']
    
    if tenant_name.blank? || csv_file.blank?
      puts "ERROR: Please specify both TENANT and CSV parameters"
      puts "Usage: bundle exec rake spree:import_orders TENANT=tenant_name CSV=path/to/orders.csv"
      exit 1
    end
    
    unless File.exist?(csv_file)
      puts "ERROR: CSV file not found: #{csv_file}"
      exit 1
    end
    
    # Switch to specific tenant
    begin
      Apartment::Tenant.switch!(tenant_name)
      puts "Switched to tenant: #{tenant_name}"
    rescue Apartment::TenantNotFound
      puts "ERROR: Tenant '#{tenant_name}' not found"
      exit 1
    end
    
    puts "Starting order import from: #{csv_file}"
    
    imported_orders = 0
    skipped_orders = 0
    line_items_created = 0
    errors = []
    current_order = nil
    
    CSV.foreach(csv_file, headers: true) do |row|
      begin
        order_number = row['Order Number']
        
        # Create new order if this is a different order number
        if current_order.nil? || current_order.number != order_number
          current_order = create_order_from_row(row)
          if current_order
            imported_orders += 1
            print "."
          else
            next # Skip to next row if order creation failed
          end
        end
        
        # Add line item to current order
        if current_order && row['Product Name'].present? && row['Product Name'] != 'Product Deleted'
          if create_line_item(current_order, row)
            line_items_created += 1
            print "+"
          else
            print "-"
          end
        end
        
      rescue => e
        error_msg = "Error processing row for order #{row['Order Number']}: #{e.message}"
        errors << error_msg
        puts "\n#{error_msg}"
      end
    end
    
    # Fix order totals and line item associations
    puts "\nFixing order totals..."
    fix_order_totals
    
    puts "\n\nImport completed!"
    puts "Orders imported: #{imported_orders}"
    puts "Line items created: #{line_items_created}"
    puts "Orders skipped: #{skipped_orders}"
    puts "Errors: #{errors.count}"
    
    if errors.any?
      puts "\nError details:"
      errors.each { |error| puts "  - #{error}" }
    end
  end
  
  private
  
  def create_order_from_row(row)
    begin
      # Skip if order already exists
      existing_order = Spree::Order.find_by(number: row['Order Number'])
      return existing_order if existing_order
      
      # Find or create user
      user = find_or_create_user(row['Customer Email'])
      
      # Create order
      order = Spree::Order.new(
        number: row['Order Number'],
        email: row['Customer Email'],
        created_at: DateTime.parse(row['Order Date']),
        completed_at: row['Completed At'].present? ? DateTime.parse(row['Completed At']) : nil,
        state: row['Order State']&.downcase || 'complete',
        payment_state: row['Payment State']&.downcase,
        total: row['Order Total'].to_f,
        currency: row['Currency'] || 'USD',
        user: user,
        store: Spree::Store.first # Use default store for tenant
      )
      
      # Create addresses
      order.bill_address = create_address(row, 'Billing')
      order.ship_address = create_address(row, 'Shipping')
      
      order.save!(validate: false)
      
      # Create payment if needed
      create_payment_for_order(order, row)
      
      order
    rescue => e
      puts "\nError creating order #{row['Order Number']}: #{e.message}"
      nil
    end
  end
  
  def create_line_item(order, row)
    begin
      # Find variant by SKU
      variant = Spree::Variant.find_by(sku: row['Product SKU']) if row['Product SKU'].present?
      variant ||= Spree::Variant.find_by(sku: row['Variant SKU']) if row['Variant SKU'].present?
      
      # Try partial SKU match (h01_Nothing -> h01)
      if variant.nil? && row['Variant SKU'].present?
        base_sku = row['Variant SKU'].split('_').first
        variant = Spree::Variant.find_by(sku: base_sku)
      end
      
      # Find by product name
      if variant.nil? && row['Product Name'].present?
        product = Spree::Product.find_by(name: row['Product Name'])
        variant = product.master if product
      end
      
      return false unless variant
      
      # Insert line item directly to avoid validation issues
      Spree::LineItem.insert({
        order_id: order.id,
        variant_id: variant.id,
        quantity: row['Quantity'].to_i,
        price: row['Price'].to_f,
        currency: order.currency,
        cost_price: row['Price'].to_f,
        created_at: Time.current,
        updated_at: Time.current
      })
      
      true
    rescue => e
      puts "\nError creating line item: #{e.message}"
      false
    end
  end
  
  def find_or_create_user(email)
    return nil if email.blank?
    
    user = Spree::User.find_by(email: email)
    return user if user
    
    # Create new user
    Spree::User.create!(
      email: email,
      password: SecureRandom.hex(8),
      password_confirmation: -> { password }
    )
  rescue => e
    puts "Warning: Could not create user #{email}: #{e.message}"
    nil
  end
  
  def create_address(row, type)
    return nil unless row["#{type} Name"].present?
    
    # Parse name
    name_parts = row["#{type} Name"].split(' ', 2)
    
    # Find or create country
    country = Spree::Country.find_by(name: row["#{type} Country"]) || 
              Spree::Country.find_by(iso: row["#{type} Country"]) ||
              Spree::Country.first
    
    # Find state
    state = if row["#{type} State"].present? && country
              country.states.find_by(name: row["#{type} State"]) ||
              country.states.find_by(abbr: row["#{type} State"])
            end
    
    Spree::Address.create!(
      firstname: name_parts[0] || '',
      lastname: name_parts[1] || '',
      address1: row["#{type} Address"] || '',
      city: row["#{type} City"] || '',
      zipcode: row["#{type} Zip"] || '',
      phone: row["#{type} Phone"] || '',
      country: country,
      state: state
    )
  rescue => e
    puts "Warning: Could not create #{type.downcase} address: #{e.message}"
    nil
  end
  
  def create_payment_for_order(order, row)
    return unless row['Payment Method'].present? && order.total > 0
    
    # Find or create payment method
    payment_method = Spree::PaymentMethod.find_by(name: row['Payment Method']) ||
                     Spree::PaymentMethod.first
    
    if payment_method
      payment = order.payments.build(
        amount: order.total,
        payment_method: payment_method,
        state: 'completed',
        number: "PAY-#{SecureRandom.hex(4).upcase}"
      )
      payment.save!(validate: false)
    end
  rescue => e
    puts "Warning: Could not create payment: #{e.message}"
  end
  
  def fix_order_totals
    Spree::Order.find_each do |order|
      order.line_items.reload
      item_total = order.line_items.sum { |li| li.price * li.quantity }
      
      order.update_columns(
        item_total: item_total,
        total: item_total,
        item_count: order.line_items.sum(:quantity)
      )
    end
    puts "Order totals fixed!"
  end
end