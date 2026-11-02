# lib/tasks/tenant.rake
namespace :tenant do
  desc "Migrate all tenants"
  task migrate: :environment do
    Apartment.tenant_names.each do |tenant|
      puts "Migrating #{tenant}..."
      Apartment::Tenant.switch!(tenant) do
        ActiveRecord::Tasks::DatabaseTasks.migrate
      end
    end
    puts "All tenants migrated successfully!"
  end
  
  desc "Create a new tenant"
  task :create, [:subdomain, :name, :email] => :environment do |t, args|
    subdomain = args[:subdomain]
    name = args[:name]
    email = args[:email]
    
    unless subdomain && name && email
      puts "Usage: rake tenant:create[subdomain,name,email]"
      exit 1
    end
    
    ActiveRecord::Base.transaction do
      # Create store
      store = Spree::Store.create!(
        name: name,
        subdomain: subdomain.downcase,
        code: name.parameterize.underscore,
        url: "http://#{subdomain}.lvh.me:3000",
        mail_from_address: email,
        default_currency: 'USD'
      )
      
      # Create tenant schema
      Apartment::Tenant.create(store.code)
      
      # Setup tenant
      Apartment::Tenant.switch!(store.code) do
        Spree::Core::Engine.load_seed
        TenantSetupService.new(store.code, { email: email }).call
      end
      
      puts "Tenant created successfully!"
      puts "Store: #{name}"
      puts "URL: http://#{subdomain}.lvh.me:3000"
      puts "Code: #{store.code}"
    end
  rescue StandardError => e
    puts "Error creating tenant: #{e.message}"
    puts e.backtrace.join("\n")
  end
  
  desc "Drop a tenant"
  task :drop, [:tenant_code] => :environment do |t, args|
    tenant_code = args[:tenant_code]
    
    unless tenant_code
      puts "Usage: rake tenant:drop[tenant_code]"
      exit 1
    end
    
    # Find and destroy store
    store = Spree::Store.find_by(code: tenant_code)
    store&.destroy
    
    # Drop tenant schema
    Apartment::Tenant.drop(tenant_code)
    
    puts "Tenant #{tenant_code} dropped successfully!"
  rescue StandardError => e
    puts "Error dropping tenant: #{e.message}"
  end
  
  desc "List all tenants"
  task list: :environment do
    puts "Available tenants:"
    Apartment.tenant_names.each do |tenant|
      store = Spree::Store.find_by(code: tenant)
      if store
        puts "- #{tenant} (#{store.name} - #{store.subdomain})"
      else
        puts "- #{tenant} (orphaned schema)"
      end
    end
  end
  
  desc "Seed all tenants"
  task seed: :environment do
    Apartment.tenant_names.each do |tenant|
      puts "Seeding #{tenant}..."
      Apartment::Tenant.switch!(tenant) do
        Spree::Core::Engine.load_seed
      end
    end
    puts "All tenants seeded successfully!"
  end
end
