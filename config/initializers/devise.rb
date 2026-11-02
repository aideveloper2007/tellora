Devise.setup do |config|
  config.secret_key = Rails.application.credentials.secret_key_base || ENV['SECRET_KEY_BASE']
  config.parent_controller = 'Spree::BaseController'
  config.mailer_sender = ENV.fetch('MAIL_FROM_ADDRESS', "support@mystore.com")
  config.parent_mailer = 'Spree::BaseMailer'
  require 'devise/orm/active_record'
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.http_authentication_realm = 'Spree Application'
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 6..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  
  # Add mapping for Spree::User to :spree_user
  config.warden do |manager|
    manager.default_strategies(scope: :spree_user).unshift :database_authenticatable
    manager.default_strategies(scope: :user).unshift :database_authenticatable
  end
  
  # Ensure both :user and :spree_user scopes are properly set up
  config.router_name = :spree
end