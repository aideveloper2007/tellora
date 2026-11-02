# app/controllers/tenant_registrations_controller.rb
class TenantRegistrationsController < ApplicationController
  require 'net/http'
  require 'uri'
  
  def new
    @user = Spree::User.new
    @store = Spree::Store.new
  end

def create
  validate_registration_params!
  
  # First, create the domains in BotGuard and Gatekeeper (outside transaction)
  subdomain = params[:store][:subdomain].downcase
  
  begin
    create_botguard_domain(subdomain)
    create_gatekeeper_domain(subdomain)
  rescue => e
    Rails.logger.error("External API Error: #{e.message}")
    flash[:error] = "Failed to create store: #{e.message}"
    render :new
    return
  end
  
  # Now do the database operations in a transaction
  ActiveRecord::Base.transaction do
    # Create store in public schema
    @store = Spree::Store.create!(
      name: params[:store][:name],
      subdomain: subdomain,
      code: generate_unique_code,
      url: generate_store_url(subdomain),
      mail_from_address: params[:user][:email],
      default_currency: 'USD',
      supported_currencies: 'USD',
      default: false
    )
    
    # Create tenant database
    Apartment::Tenant.create(@store.code)
    
    # Switch to tenant and create admin user
    Apartment::Tenant.switch(@store.code) do
      # Load Spree seeds for this tenant
      Spree::Core::Engine.load_seed
      
      # Create admin user in tenant database
      admin_user = Spree::User.create!(
        email: params[:user][:email],
        password: params[:user][:password],
        password_confirmation: params[:user][:password_confirmation],
        login: params[:user][:email]
      )
      
      # Assign admin role
      admin_user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
      
      # Create a default store for this tenant
      tenant_store = Spree::Store.create!(
        name: @store.name,
        code: @store.code,
        url: @store.url,
        mail_from_address: @store.mail_from_address,
        default_currency: 'USD',
        supported_currencies: 'USD',
        default: true
      )
    end
    
    # Redirect to theme onboarding instead of login
    redirect_to generate_theme_onboarding_url(@store.subdomain), 
                allow_other_host: true,
                notice: "Store created successfully! Let's create your theme..."
  end
rescue => e
  Rails.logger.error("Store Creation Failed: #{e.message}")
  Rails.logger.error(e.backtrace.join("\n"))
  
  # Clean up database if it was created
  if @store&.persisted?
    begin
      Apartment::Tenant.drop(@store.code) rescue nil
      @store.destroy
    rescue => cleanup_error
      Rails.logger.error("Cleanup failed: #{cleanup_error.message}")
    end
  end
  
  flash[:error] = "Failed to create store: #{e.message}"
  render :new
end

  private

def create_botguard_domain(subdomain)
  domain = "#{subdomain}.zencommerce.xyz"
  
  uri = URI.parse("https://apiv2.botguard.net/website")
  
  request = Net::HTTP::Post.new(uri)
  request["accept"] = "application/json"
  request["Authorization"] = "Bearer a99410b4-b112-40d4-b684-f47ad6a782ef"
  request["Content-Type"] = "application/x-www-form-urlencoded"
  
  request.body = URI.encode_www_form({
    domain: domain,
    user: ""
  })
  
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  
  # Accept 200, 201, and 303 as success codes
  if [200, 201, 303].include?(response.code.to_i)
    Rails.logger.info("✅ BotGuard domain created: #{domain} (Response: #{response.code})")
  else
    Rails.logger.error("❌ BotGuard domain creation failed: #{response.code} - #{response.body}")
    raise "Failed to create BotGuard domain: #{response.body}"
  end
rescue => e
  Rails.logger.error("BotGuard API Error: #{e.message}")
  raise "Failed to create domain in BotGuard: #{e.message}"
end

  def create_gatekeeper_domain(subdomain)
    domain = if Rails.env.production?
               "#{subdomain}.zencommerce.xyz"
             else
               "#{subdomain}.zencommerce.xyz"
             end
    
    backend_ip = "148.251.69.56"
    
    uri = URI.parse("http://157.180.75.35/domains/create")
    
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = false
    http.read_timeout = 30
    
    request = Net::HTTP::Post.new(uri)
    request.basic_auth('botguard', 'a99410b4-b112-40d4-b684-f47ad6a782ef')
    
    # Create multipart form data
    boundary = "----WebKitFormBoundary#{rand(10**16)}"
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    
    # Build the multipart body
    body = []
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"domain\"\r\n\r\n"
    body << "#{domain}\r\n"
    
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"backend\"\r\n\r\n"
    body << "#{backend_ip}\r\n"
    
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"backend_port\"\r\n\r\n"
    body << "443\r\n"
    
    body << "--#{boundary}--\r\n"
    
    request.body = body.join
    
    response = http.request(request)
    
    if response.code.to_i == 302 || response.code.to_i == 301 || response.code.to_i == 200
      Rails.logger.info("✅ Gatekeeper domain created: #{domain}")
    else
      Rails.logger.error("❌ Gatekeeper domain creation failed: #{response.code}")
      raise "Failed to create Gatekeeper domain: #{response.code}"
    end
  rescue => e
    Rails.logger.error("Gatekeeper API Error: #{e.message}")
    raise "Failed to create domain in Gatekeeper: #{e.message}"
  end

  def validate_registration_params!
    raise ArgumentError, "Email is required" if params[:user][:email].blank?
    raise ArgumentError, "Password is required" if params[:user][:password].blank?
    raise ArgumentError, "Passwords do not match" if params[:user][:password] != params[:user][:password_confirmation]
    raise ArgumentError, "Store name is required" if params[:store][:name].blank?
    raise ArgumentError, "Subdomain is required" if params[:store][:subdomain].blank?
    
    # Subdomain validation
    subdomain = params[:store][:subdomain].downcase
    unless subdomain =~ /\A[a-z0-9]+\z/
      raise ArgumentError, "Subdomain must be lowercase alphanumeric characters only"
    end
    
    # Check if subdomain is already taken
    if Spree::Store.exists?(subdomain: subdomain)
      raise ArgumentError, "Subdomain '#{subdomain}' is already taken"
    end
    
    # Check reserved subdomains
    reserved = %w[www api admin mail ftp public app assets cdn blog help support docs]
    if reserved.include?(subdomain)
      raise ArgumentError, "Subdomain '#{subdomain}' is reserved"
    end
  end

  def generate_unique_code
    base_code = params[:store][:name].parameterize
    unique_code = base_code
    counter = 1
    
    while Spree::Store.exists?(code: unique_code)
      unique_code = "#{base_code}-#{counter}"
      counter += 1
    end
    
    unique_code
  end

  def generate_store_url(subdomain)
    subdomain = subdomain.downcase
    
    if Rails.env.production?
      "https://#{subdomain}.zencommerce.xyz"
    else
      "http://#{subdomain}.lvh.me:3000"
    end
  end

  def generate_login_url(subdomain)
    subdomain = subdomain.downcase
    
    if Rails.env.production?
      "https://#{subdomain}.zencommerce.xyz/user/sign_in"
    else
      "http://#{subdomain}.lvh.me:3000/user/sign_in"
    end
  end
  
  def generate_theme_onboarding_url(subdomain)
    subdomain = subdomain.downcase
    
    if Rails.env.production?
      "https://#{subdomain}.zencommerce.xyz/genai_themes?onboarding=true"
    else
      "http://#{subdomain}.lvh.me:3000/genai_themes?onboarding=true"
    end
  end
end