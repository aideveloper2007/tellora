# app/controllers/api/v1/stores_controller.rb
class Api::V1::StoresController < ApplicationController
  protect_from_forgery with: :null_session
  before_action :authenticate_api_key
  
  def create
    Rails.logger.info "=== Store Creation Request ==="
    Rails.logger.info "Params: #{store_params.inspect}"
    
    begin
      # Find existing user by email
      user = User.find_by(email: store_params[:store_owner_email])
      
      unless user
        render json: {
          success: false,
          message: "User not found",
          errors: ["No user found with email: #{store_params[:store_owner_email]}"]
        }, status: :not_found
        return
      end
      
      Rails.logger.info "Found user: #{user.email}"
      
      # Generate unique code for tenant
      tenant_code = generate_unique_code(store_params[:name])
      subdomain = store_params[:handle] || tenant_code
      
      # Generate store URL
      store_url = generate_store_url(subdomain)
      
      ActiveRecord::Base.transaction do
        # Create store in public schema
        store = Spree::Store.create!(
          name: store_params[:name],
          subdomain: subdomain,
          code: tenant_code,
          url: store_url,
          mail_from_address: user.email,
          default_currency: store_params[:currency] || 'USD',
          supported_currencies: store_params[:currency] || 'USD',
          default: false
        )
        
        Rails.logger.info "Created store in public schema: #{store.name}"
        
        # Create tenant database
        Apartment::Tenant.create(tenant_code)
        Rails.logger.info "Created tenant database: #{tenant_code}"
        
        # Switch to tenant and create admin user + setup
        Apartment::Tenant.switch(tenant_code) do
          # Load Spree seeds for this tenant
          Spree::Core::Engine.load_seed
          Rails.logger.info "Loaded Spree seeds for tenant"
          
          # Create admin user in tenant database using main User details
          admin_user = Spree::User.create!(
            email: user.email,
            password: 'TempPassword123!', # Default password for tenant admin
            password_confirmation: 'TempPassword123!',
            login: user.email
          )
          
          # Assign admin role
          admin_user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
          Rails.logger.info "Created admin user in tenant: #{admin_user.email}"
          
          # Create a default store for this tenant
          tenant_store = Spree::Store.create!(
            name: store.name,
            code: store.code,
            url: store.url,
            mail_from_address: store.mail_from_address,
            default_currency: store_params[:currency] || 'USD',
            supported_currencies: store_params[:currency] || 'USD',
            default: true
          )
          Rails.logger.info "Created tenant store: #{tenant_store.name}"
          
          # Run tenant setup service
          TenantSetupService.new(tenant_code, {
            email: user.email,
            name: user.name,
            surname: user.surname
          }).call
          Rails.logger.info "Completed tenant setup"
        end
        
        Rails.logger.info "Store creation completed successfully"
        
        render json: {
          success: true,
          message: "Store created successfully",
          data: {
            store_id: store.id,
            name: store.name,
            handle: subdomain,
            tenant_code: tenant_code,
            url: store.url,
            login_url: generate_login_url(subdomain),
            currency: store.default_currency,
            admin_email: user.email,
            admin_temp_password: 'TempPassword123!',
            user_details: {
              id: user.id,
              name: user.name,
              surname: user.surname,
              country: user.country
            },
            created_at: store.created_at
          }
        }, status: :created
      end
      
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Store validation failed: #{e.message}"
      
      # Clean up if tenant was created but store creation failed
      begin
        Apartment::Tenant.drop(tenant_code) if defined?(tenant_code)
      rescue => cleanup_error
        Rails.logger.error "Cleanup failed: #{cleanup_error.message}"
      end
      
      render json: {
        success: false,
        message: "Store validation failed",
        errors: e.record.errors.full_messages
      }, status: :unprocessable_entity
      
    rescue Apartment::TenantExists => e
      Rails.logger.error "Tenant already exists: #{e.message}"
      
      render json: {
        success: false,
        message: "Store already exists",
        errors: ["A store with this name already exists"]
      }, status: :conflict
      
    rescue => e
      Rails.logger.error "Store creation error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Clean up if tenant was created
      begin
        Apartment::Tenant.drop(tenant_code) if defined?(tenant_code)
      rescue => cleanup_error
        Rails.logger.error "Cleanup failed: #{cleanup_error.message}"
      end
      
      render json: {
        success: false,
        message: "Internal server error",
        errors: [e.message]
      }, status: :internal_server_error
    end
  end
  
  private
  
  def authenticate_api_key
    api_key = request.headers['Authorization']&.gsub('Bearer ', '')
    
    unless api_key == Rails.application.credentials.dig(:lms_api_key)
      render json: { 
        success: false,
        message: 'Unauthorized - Invalid API Key' 
      }, status: :unauthorized
    end
  end
  
  def store_params
    params.permit(:store_owner_email, :currency, :country, :name, :handle, :timezone)
      .tap do |permitted|
        # Clean up email
        permitted[:store_owner_email] = permitted[:store_owner_email]&.downcase&.strip
        
        # Clean up handle
        if permitted[:handle].present?
          permitted[:handle] = permitted[:handle].downcase.strip
        end
        
        # Set defaults
        permitted[:currency] = 'USD' if permitted[:currency].blank?
        permitted[:country] = 'US' if permitted[:country].blank?
        permitted[:timezone] = 'UTC' if permitted[:timezone].blank?
      end
  end
  
  def generate_unique_code(store_name)
    base_code = store_name.parameterize
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
end