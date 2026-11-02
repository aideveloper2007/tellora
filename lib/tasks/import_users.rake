# Save as: lib/tasks/import_users.rake
# Run on NEW server

require 'csv'

namespace :spree do
  desc "Import users from CSV for specific tenant"
  task import_users: :environment do
    
    # Get parameters
    tenant_name = ENV['TENANT'] || ENV['tenant']
    csv_file = ENV['CSV'] || ENV['csv']
    
    if tenant_name.blank? || csv_file.blank?
      puts "ERROR: Please specify both TENANT and CSV parameters"
      puts "Usage: bundle exec rake spree:import_users TENANT=tenant_name CSV=path/to/users.csv"
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
    
    puts "Starting user import from: #{csv_file}"
    
    imported_users = 0
    updated_users = 0
    skipped_users = 0
    addresses_created = 0
    errors = []
    
    CSV.foreach(csv_file, headers: true) do |row|
      begin
        email = row['Email']
        
        # Skip if email is blank
        if email.blank?
          skipped_users += 1
          print "s"
          next
        end
        
        # Find or create user
        user = create_or_update_user_from_row(row)
        if user
          if user.previously_new_record?
            imported_users += 1
            print "+"
          else
            updated_users += 1
            print "."
          end
          
          # Create addresses
          addresses_created += create_addresses_for_user(user, row)
        else
          skipped_users += 1
          print "s"
        end
        
      rescue => e
        error_msg = "Error processing user #{row['Email']}: #{e.message}"
        errors << error_msg
        puts "\n#{error_msg}"
        print "E"
      end
    end
    
    puts "\n\nImport completed!"
    puts "Users imported: #{imported_users}"
    puts "Users updated: #{updated_users}"
    puts "Users skipped: #{skipped_users}"
    puts "Addresses created: #{addresses_created}"
    puts "Errors: #{errors.count}"
    
    if errors.any?
      puts "\nError details:"
      errors.each { |error| puts "  - #{error}" }
    end
  end
  
  private
  
  def create_or_update_user_from_row(row)
    begin
      email = row['Email'].strip.downcase
      
      # Find existing user or initialize new one
      user = Spree::User.find_by(email: email)
      is_new = user.nil?
      user ||= Spree::User.new(email: email)
      
      # Set basic user attributes that should exist
      basic_attributes = {
        first_name: row['First Name'],
        last_name: row['Last Name'],
        created_at: parse_datetime(row['Created At']) || Time.current,
        updated_at: parse_datetime(row['Updated At']) || Time.current
      }
      
      # Add optional attributes only if they exist on the model
      optional_attributes = {
        'login' => row['Login'],
        'deleted_at' => parse_datetime(row['Deleted At']),
        'confirmed_at' => parse_datetime(row['Confirmed At']),
        'confirmation_sent_at' => parse_datetime(row['Confirmation Sent At']),
        'reset_password_sent_at' => parse_datetime(row['Reset Password Sent At']),
        'remember_created_at' => parse_datetime(row['Remember Created At']),
        'sign_in_count' => row['Sign In Count'].to_i,
        'current_sign_in_at' => parse_datetime(row['Current Sign In At']),
        'last_sign_in_at' => parse_datetime(row['Last Sign In At']),
        'current_sign_in_ip' => row['Current Sign In IP'],
        'last_sign_in_ip' => row['Last Sign In IP'],
        'failed_attempts' => row['Failed Attempts'].to_i,
        'unlock_token' => row['Unlock Token'],
        'locked_at' => parse_datetime(row['Locked At']),
        'spree_api_key' => row['Spree API Key']
      }
      
      # Only add attributes that exist on the model
      optional_attributes.each do |attr_name, value|
        if user.respond_to?("#{attr_name}=")
          basic_attributes[attr_name.to_sym] = value
        end
      end
      
      user.assign_attributes(basic_attributes)
      
      # Set password for new users
      if is_new
        password = SecureRandom.hex(8)
        user.password = password
        user.password_confirmation = password
      end
      
      user.save!(validate: false)
      user
      
    rescue => e
      puts "\nError creating/updating user #{row['Email']}: #{e.message}"
      nil
    end
  end
  
  def create_addresses_for_user(user, row)
    addresses_count = 0
    
    # Create billing address
    if has_address_data?(row, 'Bill Address')
      bill_address = create_address_from_row(row, 'Bill Address')
      if bill_address
        user.update_column(:bill_address_id, bill_address.id)
        addresses_count += 1
      end
    end
    
    # Create shipping address
    if has_address_data?(row, 'Ship Address')
      ship_address = create_address_from_row(row, 'Ship Address')
      if ship_address
        user.update_column(:ship_address_id, ship_address.id)
        addresses_count += 1
      end
    end
    
    addresses_count
  rescue => e
    puts "\nWarning: Could not create addresses for user #{user.email}: #{e.message}"
    0
  end
  
  def create_address_from_row(row, type)
    return nil unless row["#{type} First Name"].present? || row["#{type} Address1"].present?
    
    # Find or create country
    country = if row["#{type} Country"].present?
                Spree::Country.find_by(name: row["#{type} Country"]) ||
                Spree::Country.find_by(iso: row["#{type} Country"]) ||
                Spree::Country.find_by(iso3: row["#{type} Country"])
              end
    country ||= Spree::Country.first
    
    # Find state
    state = if row["#{type} State"].present? && country
              country.states.find_by(name: row["#{type} State"]) ||
              country.states.find_by(abbr: row["#{type} State"])
            end
    
    address = Spree::Address.new(
      firstname: row["#{type} First Name"] || '',
      lastname: row["#{type} Last Name"] || '',
      address1: row["#{type} Address1"] || '',
      address2: row["#{type} Address2"] || '',
      city: row["#{type} City"] || '',
      zipcode: row["#{type} Zipcode"] || '',
      phone: row["#{type} Phone"] || '',
      country: country,
      state: state
    )
    
    # If state not found but state text exists, use state_name
    if row["#{type} State"].present? && state.nil?
      address.state_name = row["#{type} State"]
    end
    
    address.save!(validate: false)
    address
    
  rescue => e
    puts "\nWarning: Could not create #{type.downcase.gsub('_', ' ')}: #{e.message}"
    nil
  end
  
  def has_address_data?(row, prefix)
    %w[First\ Name Last\ Name Address1 City].any? do |field|
      row["#{prefix} #{field}"].present?
    end
  end
  
  def parse_datetime(datetime_string)
    return nil if datetime_string.blank?
    begin
      DateTime.parse(datetime_string)
    rescue ArgumentError
      nil
    end
  end
end