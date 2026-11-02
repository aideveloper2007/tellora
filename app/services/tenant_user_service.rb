# app/services/tenant_user_service.rb
class TenantUserService
  class TenantNotFound < StandardError; end
  class UserCreationError < StandardError; end
  
  def self.create_admin_user(tenant_code, user_attributes, setup_tenant: false)
    new(tenant_code).create_admin_user(user_attributes, setup_tenant: setup_tenant)
  end
  
  def self.find_user(tenant_code, user_id)
    new(tenant_code).find_user(user_id)
  end
  
  def self.list_admin_users(tenant_code, limit: 50)
    new(tenant_code).list_admin_users(limit)
  end
  
  def initialize(tenant_code)
    @tenant_code = tenant_code.to_s.downcase.strip
    validate_tenant_exists!
  end
  
  def create_admin_user(user_attributes, setup_tenant: false)
    Apartment::Tenant.switch(@tenant_code) do
      ActiveRecord::Base.transaction do
        user = Spree::User.create!(user_attributes)
        assign_admin_role(user)
        
        # Run tenant setup if requested (useful for first admin user)
        if setup_tenant
          TenantSetupService.new(@tenant_code, user_attributes).call
        end
        
        user
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    raise UserCreationError, "User validation failed: #{e.record.errors.full_messages.join(', ')}"
  rescue => e
    raise UserCreationError, "Failed to create user: #{e.message}"
  end
  
  def find_user(user_id)
    Apartment::Tenant.switch(@tenant_code) do
      Spree::User.find(user_id)
    end
  end
  
  def list_admin_users(limit = 50)
    Apartment::Tenant.switch(@tenant_code) do
      Spree::User.joins(:spree_roles)
                 .where(spree_roles: { name: 'admin' })
                 .distinct
                 .limit(limit)
    end
  end
  
  def tenant_info
    Apartment::Tenant.switch('public') do
      Spree::Store.find_by!(code: @tenant_code)
    end
  end
  
  private
  
  def validate_tenant_exists!
    # Check if tenant exists in public schema
    tenant_exists = false
    Apartment::Tenant.switch('public') do
      tenant_exists = Spree::Store.exists?(code: @tenant_code)
    end
    
    raise TenantNotFound, "Store with code '#{@tenant_code}' does not exist" unless tenant_exists
    
    # Check if tenant database exists
    unless Apartment.tenant_names.include?(@tenant_code)
      raise TenantNotFound, "Database for tenant '#{@tenant_code}' does not exist"
    end
  end
  
  def assign_admin_role(user)
    admin_role = Spree::Role.find_or_create_by!(name: 'admin')
    user.spree_roles << admin_role unless user.spree_roles.include?(admin_role)
  end
end