# frozen_string_literal: true

# A custom domain a store owner connects to their Tellora store.
#
# Flow (status):
#   pending  -> the owner adds the DNS records we show; DomainCheckJob checks them
#   issuing  -> DNS is correct; the certbot agent is getting a free SSL certificate
#   active   -> SSL issued; the store answers on this domain
#   failed   -> SSL could not be issued (the owner presses "Check again" to retry)
#   removing -> the owner removed it; the certbot agent deletes the certificate, then the row
#
# Excluded from Apartment: always stored in the public schema.
class StoreDomain < ApplicationRecord
  STATUSES = %w[pending issuing active failed removing].freeze
  SERVING_STATUSES = %w[active].freeze
  TXT_PREFIX = '_tellora'
  TOKEN_PREFIX = 'tellora-verify='

  # Second-level suffixes where the registrable domain has three labels (mybrand.co.in)
  MULTI_PART_SUFFIXES = %w[
    co.in net.in org.in firm.in gen.in ind.in ac.in edu.in gov.in res.in
    co.uk org.uk me.uk ltd.uk plc.uk ac.uk gov.uk
    com.au net.au org.au edu.au gov.au
    co.nz net.nz org.nz
    com.br net.br org.br
    com.sg edu.sg org.sg net.sg
    com.my net.my org.my
    co.za org.za
    co.jp ne.jp or.jp
    com.mx com.ar com.co com.pe com.ng com.gh com.pk com.bd com.lk com.np com.ph com.vn com.tr com.eg com.sa
    co.ke co.tz co.ug co.id co.th co.kr co.il
    ae.org com.hk com.tw com.cn
  ].freeze

  HOST_FORMAT = /\A(?=.{4,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

  validates :store_id, :tenant_code, :host, :primary_host, :verification_token, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :host, format: { with: HOST_FORMAT, message: 'is not a valid domain name' }
  validates :host, uniqueness: { message: 'is already connected to a store' }
  validates :primary_host, uniqueness: { message: 'is already connected to a store' }
  validate :not_a_platform_domain
  validate :one_domain_per_store, on: :create

  before_validation :prepare, on: :create

  scope :serving, -> { where(status: SERVING_STATUSES) }

  class << self
    # "https://WWW.MyBrand.com/shop?x=1" -> "www.mybrand.com"
    def normalize(input)
      value = input.to_s.strip.downcase
      value = value.sub(%r{\A[a-z][a-z0-9+.-]*://}, '')
      value = value.split(%r{[/?#]}).first.to_s
      value = value.split('@').last.to_s
      value = value.split(':').first.to_s
      value.chomp('.')
    end

    # "shop.mybrand.co.in" -> "mybrand.co.in"
    def registrable_domain(host)
      labels = host.split('.')
      return host if labels.size <= 2

      if defined?(PublicSuffix)
        begin
          return PublicSuffix.domain(host) || host
        rescue StandardError
          # fall through to the simple rules
        end
      end

      last_two = labels.last(2).join('.')
      MULTI_PART_SUFFIXES.include?(last_two) ? labels.last(3).join('.') : last_two
    end

    # Tenant code of the store serving this host (custom domains only), or nil
    def tenant_for_host(host)
      host = normalize(host)
      return nil if host.empty?

      serving.where(primary_host: host).or(serving.where(host: host))
             .or(serving.where(apex: true, host: host.delete_prefix('www.')))
             .pick(:tenant_code)
    end

    # Primary host of the store's active custom domain, cached (used to redirect the Tellora subdomain)
    def primary_host_for(tenant)
      Rails.cache.fetch("store_domain:primary:#{tenant}", expires_in: 5.minutes) do
        serving.where(tenant_code: tenant).order(:id).pick(:primary_host) || ''
      end.presence
    rescue StandardError
      nil
    end

    def forget(tenant)
      Rails.cache.delete("store_domain:primary:#{tenant}")
    rescue StandardError
      nil
    end
  end

  # Every hostname this domain answers on (and needs in the SSL certificate)
  def hostnames
    apex? ? [host, "www.#{host}"] : [host]
  end

  # DNS records the owner must add, with names relative to their registrable domain
  def dns_records(store_host:, server_ip:)
    base = self.class.registrable_domain(host)
    relative = lambda do |name|
      name == base ? '@' : name.delete_suffix(".#{base}")
    end

    records = []
    if apex?
      records << { key: 'apex', type: 'A', name: '@', value: server_ip, purpose: "Points #{host} to your store" }
      records << { key: 'www', type: 'CNAME', name: 'www', value: store_host, purpose: "Points www.#{host} to your store" }
    else
      records << { key: 'host', type: 'CNAME', name: relative.call(host), value: store_host, purpose: "Points #{host} to your store" }
    end
    records << { key: 'txt', type: 'TXT', name: relative.call(txt_name), value: txt_value, purpose: 'Proves you own the domain' }
    records
  end

  def txt_name
    "#{TXT_PREFIX}.#{host}"
  end

  def txt_value
    "#{TOKEN_PREFIX}#{verification_token}"
  end

  def cert_name
    host
  end

  STATUSES.each do |name|
    define_method("#{name}?") { status == name }
  end

  private

  def prepare
    entered = self.class.normalize(host)
    base = entered.delete_prefix('www.')

    if self.class.registrable_domain(base) == base
      # mybrand.com or www.mybrand.com: connect both, visitors end up on the chosen one
      self.host = base
      self.apex = true
      self.primary_host = primary_host.to_s == base ? base : "www.#{base}"
    else
      # shop.mybrand.com: just that address
      self.host = entered
      self.apex = false
      self.primary_host = entered
    end

    self.verification_token ||= SecureRandom.alphanumeric(24).downcase
    self.status ||= 'pending'
  end

  def not_a_platform_domain
    return if host.blank?

    if TenantResolver.platform_domains.any? { |d| host == d || host.end_with?(".#{d}") }
      errors.add(:host, 'is a Tellora address. Enter a domain you own, like mybrand.com')
    end
  end

  def one_domain_per_store
    return unless StoreDomain.where(tenant_code: tenant_code).where.not(status: 'removing').exists?

    errors.add(:base, 'This store already has a domain. Remove it first to connect a different one.')
  end
end
