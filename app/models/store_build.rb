# frozen_string_literal: true

# A request to build a new store from the platform landing page.
# Stored in the public schema (Apartment excluded model), tracked step by step by StoreProvisioner.
class StoreBuild < ApplicationRecord
  STEPS = [
    ['store',    'Creating your store'],
    ['theme',    'Designing your theme'],
    ['apply',    'Applying the design'],
    ['products', 'Adding starter products']
  ].freeze
  STEP_KEYS = STEPS.map(&:first).freeze
  # Extra step for "Move my store" builds, right after the store is created
  IMPORT_STEP = ['import', 'Reading your current store'].freeze
  SCREENSHOT_STEP = ['import', 'Rebuilding your design from your screenshots (about 10 minutes)'].freeze

  STATUSES = %w[queued running done failed].freeze
  CURRENCIES = %w[USD EUR GBP INR AUD CAD SGD AED JPY BRL MXN ZAR NGN KES IDR].freeze

  SUBDOMAIN_FORMAT = /\A[a-z0-9]{3,30}\z/
  RESERVED = (TenantResolver::RESERVED_SUBDOMAINS + %w[public spree tellora builds start shop store stores
                                                     account login signup billing status]).freeze

  MAX_BUILDS_PER_IP_PER_DAY = ENV.fetch('MAX_BUILDS_PER_IP_PER_DAY', 3).to_i

  attr_accessor :password

  before_validation :normalize, on: :create
  before_validation :assign_token, on: :create

  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :prompt, presence: true, length: { maximum: 500 }
  validates :store_name, presence: true, length: { maximum: 60 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :password, presence: true, length: { minimum: 8, maximum: 128 }, on: :create
  validates :subdomain, presence: true
  validate  :subdomain_rules, on: :create
  validate  :within_daily_limit, on: :create

  before_create :digest_password

  # ---- publishing -----------------------------------------------------------

  # The finished build for a store, if the store was created by the store builder
  def self.for_tenant(tenant)
    where(tenant_code: tenant, status: 'done').order(:id).last
  end

  # True only for builder-created stores the owner hasn't published yet.
  # Stores created any other way (older stores) are always public.
  def self.private_store?(tenant)
    return false if tenant.blank? || tenant == TenantResolver::PUBLIC

    where(tenant_code: tenant, published_at: nil).where.not(status: 'failed').exists?
  end

  def published?
    published_at.present?
  end

  def publish!
    update!(published_at: Time.current) unless published?
  end

  # The person who built the store (or any admin of it)
  def owner?(user)
    return false unless user
    return true if user.id == admin_user_id

    user.respond_to?(:has_spree_role?) ? user.has_spree_role?('admin') : user.spree_roles.exists?(name: 'admin')
  end

  # ---- moving an existing store ---------------------------------------------

  # True when the owner is moving an existing store to Tellora
  def import?
    screenshot_import? || source_url.present?
  end

  # Moving by uploaded screenshots: the design is rebuilt from them (MirrorDesign)
  def screenshot_import?
    import_dir.present?
  end

  def source_host
    URI.parse(source_url.to_s).host.to_s.sub(/\Awww\./, '')
  rescue URI::InvalidURIError
    ''
  end

  # ---- status helpers -------------------------------------------------------

  def steps
    return STEPS unless import?

    [STEPS.first, screenshot_import? ? SCREENSHOT_STEP : IMPORT_STEP, *STEPS.drop(1)]
  end

  def step_keys
    steps.map(&:first)
  end

  def reached?(step)
    return false if completed_step.blank?

    keys = step_keys
    return false unless keys.index(step) && keys.index(completed_step)

    keys.index(completed_step) >= keys.index(step)
  end

  def current_step
    return nil if status == 'done'

    keys = step_keys
    return keys.first if completed_step.blank?

    keys[keys.index(completed_step).to_i + 1]
  end

  def complete_step!(step)
    update!(completed_step: step)
  end

  def mark_running!
    update!(status: 'running', error: nil, started_at: started_at || Time.current)
  end

  def mark_done!
    update!(status: 'done', finished_at: Time.current)
  end

  def mark_failed!(message)
    update!(status: 'failed', error: message.to_s.truncate(1000))
  end

  def steps_for_display
    steps.map do |key, label|
      state =
        if reached?(key) then 'done'
        elsif key == current_step && status == 'failed' then 'failed'
        elsif key == current_step && %w[queued running].include?(status) then 'active'
        else 'pending'
        end
      { key: key, label: label, state: state }
    end
  end

  private

  def normalize
    self.subdomain = subdomain.to_s.downcase.strip
    self.email = email.to_s.downcase.strip
    self.store_name = store_name.to_s.strip
    self.prompt = prompt.to_s.strip
    self.currency = currency.to_s.upcase.presence || 'USD'
    self.tenant_code = subdomain
  end

  def assign_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end

  def digest_password
    self.encrypted_password = Devise::Encryptor.digest(Spree.user_class, password)
  end

  def subdomain_rules
    return if subdomain.blank?

    unless subdomain.match?(SUBDOMAIN_FORMAT)
      errors.add(:subdomain, 'must be 3 to 30 lowercase letters or numbers, with no spaces or symbols')
      return
    end

    if RESERVED.include?(subdomain)
      errors.add(:subdomain, 'is reserved. Please choose another one')
      return
    end

    taken = Spree::Store.where(code: subdomain).exists? ||
            (Spree::Store.column_names.include?('subdomain') && Spree::Store.where(subdomain: subdomain).exists?) ||
            StoreBuild.where(subdomain: subdomain).where.not(status: 'failed').exists? ||
            schema_exists?(subdomain)
    errors.add(:subdomain, 'is already taken. Please choose another one') if taken
  end

  def within_daily_limit
    return if ip.blank? || MAX_BUILDS_PER_IP_PER_DAY <= 0

    recent = StoreBuild.where(ip: ip).where('created_at > ?', 24.hours.ago).count
    return if recent < MAX_BUILDS_PER_IP_PER_DAY

    errors.add(:base, "You can create up to #{MAX_BUILDS_PER_IP_PER_DAY} stores per day. Please try again tomorrow.")
  end

  def schema_exists?(name)
    connection = ActiveRecord::Base.connection
    connection.select_value("SELECT 1 FROM pg_namespace WHERE nspname = #{connection.quote(name)}").present?
  end
end