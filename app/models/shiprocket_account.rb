# frozen_string_literal: true

# A store's connection to the owner's own Shiprocket account (an API user).
# Excluded from Apartment: always stored in the public schema, one row per store.
#
# The password is encrypted with a key derived from the app's secret_key_base,
# and is never shown again after it is saved.
class ShiprocketAccount < ApplicationRecord
  validates :store_id, :tenant_code, :email, :password_encrypted, :webhook_token, presence: true
  validates :tenant_code, uniqueness: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: 'is not a valid email address' }
  validates :fallback_rate, numericality: { greater_than_or_equal_to: 0, less_than: 100_000 }

  before_validation { self.webhook_token ||= SecureRandom.hex(20) }

  def self.for_tenant(tenant_code = Apartment::Tenant.current)
    find_by(tenant_code: tenant_code)
  end

  def password=(value)
    self.password_encrypted = value.present? ? self.class.encryptor.encrypt_and_sign(value.to_s) : nil
  end

  def password
    password_encrypted.present? ? self.class.encryptor.decrypt_and_verify(password_encrypted) : nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def ready?
    pickup_location.present? && pickup_postcode.present?
  end

  def client
    Shiprocket::Client.new(self)
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key('tellora shiprocket password', ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end
end
