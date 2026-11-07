# frozen_string_literal: true

# Builds a complete store for a StoreBuild, step by step:
#
#   store    -> store record (public schema), its own tenant schema, Spree seed data, admin user
#   import   -> only for "Move my store": read the owner's existing store (SiteImport)
#   theme    -> AI theme generated from the owner's description (GenAI Theme API)
#   apply    -> theme saved in the store, images attached, set as the active theme
#   products -> AI starter products (SampleProductsGenerator)
#
# Every step is safe to run again, so "Try again" continues from the step that failed.
class StoreProvisioner
  THEME_TIMEOUT = 5 * 60 # seconds
  THEME_POLL_EVERY = 3   # seconds

  def initialize(build)
    @build = build
  end

  def call
    @build.mark_running!

    create_store   unless @build.reached?('store')
    import_site    if @build.import? && !@build.reached?('import')
    generate_theme unless @build.reached?('theme')
    apply_theme    unless @build.reached?('apply')
    add_products   unless @build.reached?('products')

    @build.mark_done!
    log "Store #{@build.tenant_code} is ready"
  rescue StandardError => e
    log "Failed at step '#{@build.current_step}': #{e.class} - #{e.message}"
    log e.backtrace.first(8).join("\n")
    @build.mark_failed!(friendly_error(e))
  end

  private

  # ---- step 1: store, schema, seeds, admin user ------------------------------

  def create_store
    code = @build.tenant_code

    store = Spree::Store.find_by(code: code) || Spree::Store.create!(store_attributes)
    @build.update!(store_id: store.id)

    Apartment::Tenant.create(code) unless schema_exists?(code)

    user_id = nil
    Apartment::Tenant.switch(code) do
      Spree::Core::Engine.load_seed unless Spree::Role.exists?(name: 'admin')
      user_id = find_or_create_admin.id
    end

    TenantResolver.clear(URI.parse(@build.store_url).host) if @build.store_url.present?
    @build.update!(admin_user_id: user_id)
    @build.complete_step!('store')
  end

  # Spree expects the store url as a bare host name ("shop.lvh.me"): it adds the
  # protocol and port itself (see app/models/spree/store_url_decorator.rb).
  def store_attributes
    attrs = {
      name: @build.store_name,
      code: @build.tenant_code,
      url: URI.parse(@build.store_url.to_s).host.presence || @build.store_url,
      mail_from_address: @build.email,
      default_currency: @build.currency,
      supported_currencies: @build.currency,
      default: false
    }
    attrs[:subdomain] = @build.subdomain if Spree::Store.column_names.include?('subdomain')
    attrs
  end

  def find_or_create_admin
    user = Spree.user_class.find_by(email: @build.email)
    unless user
      temp = SecureRandom.base58(32)
      user = Spree.user_class.new(email: @build.email, password: temp, password_confirmation: temp)
      user.login = @build.email if user.respond_to?(:login=)
      user.save!
      # Use the owner's chosen password (stored only as a Devise digest)
      user.update_column(:encrypted_password, @build.encrypted_password)
    end

    admin_role = Spree::Role.find_or_create_by!(name: 'admin')
    user.spree_roles << admin_role unless user.spree_roles.include?(admin_role)
    user
  end

  # ---- step 1b: read the existing store ("Move my store") -----------------------

  def import_site
    data = SiteImport.read(@build)
    description = data['description'].to_s.squish.truncate(480).presence || @build.prompt
    @build.update!(brand: data, prompt: description)
    @build.complete_step!('import')
  end

  # ---- step 2: AI theme --------------------------------------------------------

  def generate_theme
    if @build.theme_api_id.blank?
      result = theme_service.generate_theme(
        store_type: @build.prompt.truncate(300),
        requirements: { 'store_name' => @build.store_name, 'description' => @build.prompt },
        use_real_llm: true
      )
      theme_id = result['theme_id'].presence or raise 'The theme service did not return a theme id'
      @build.update!(theme_api_id: theme_id)
    end

    wait_for_theme!
    @build.complete_step!('theme')
  end

  def wait_for_theme!
    deadline = Time.current + THEME_TIMEOUT
    loop do
      status = theme_service.get_theme_status(theme_id: @build.theme_api_id)
      case status['status'].to_s
      when 'completed' then return status
      when 'failed', 'error' then raise "Theme generation failed: #{status['error'] || status['message'] || 'unknown error'}"
      end
      raise 'Theme generation took too long' if Time.current > deadline

      sleep THEME_POLL_EVERY
    end
  end

  # ---- step 3: apply theme -----------------------------------------------------

  def apply_theme
    status = theme_service.get_theme_status(theme_id: @build.theme_api_id)

    Apartment::Tenant.switch(@build.tenant_code) do
      store = Spree::Store.find(@build.store_id)
      # Only skip when a finished design is already live (a failed earlier try can leave an unused theme behind)
      unless store.themes.where(type: 'Spree::Themes::GenAi', default: true).exists?
        imported = @build.import? ? @build.brand : nil
        ThemeApplier.new(store: store, store_name: @build.store_name, prompt: @build.prompt, imported: imported)
                    .apply!(status['theme_data'])
      end
      SiteImport.attach_logo(store, @build.brand.dig('brand', 'logo_url')) if @build.import? && @build.brand.is_a?(Hash)
    end

    @build.complete_step!('apply')
  end

  # ---- step 4: starter products ------------------------------------------------

  def add_products
    Apartment::Tenant.switch(@build.tenant_code) do
      store = Spree::Store.find(@build.store_id)
      SampleProductsGenerator.new(store: store, store_type: @build.prompt).call
    end
    @build.complete_step!('products')
  end

  # ---- helpers -------------------------------------------------------------------

  def theme_service
    @theme_service ||= GenaiThemeService.new(tenant_id: @build.tenant_code, user_id: @build.admin_user_id)
  end

  def schema_exists?(name)
    connection = ActiveRecord::Base.connection
    connection.select_value("SELECT 1 FROM pg_namespace WHERE nspname = #{connection.quote(name)}").present?
  end

  # Message shown to the store owner: what failed, without internal details
  def friendly_error(error)
    step = @build.steps.to_h[@build.current_step] || 'Building your store'
    detail =
      case error
      when ActiveRecord::RecordInvalid then error.record.errors.full_messages.to_sentence
      when Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED then 'The design service did not respond'
      else error.message.to_s.truncate(200)
      end
    "#{step} did not finish: #{detail}"
  end

  def log(message)
    Rails.logger.info "[StoreProvisioner #{@build.token}] #{message}"
  end
end