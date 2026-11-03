require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }
  config.active_storage.service = :local
  config.assume_ssl = ENV.fetch("FORCE_SSL", "true") == "true"
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false

  # Links in emails (password reset, order confirmations) point to the platform domain
  mailer_host = ENV.fetch("MAILER_HOST") { ENV.fetch("TENANT_DOMAINS", "localhost").split(",").first.strip }
  config.action_mailer.default_url_options = { host: mailer_host, protocol: config.force_ssl ? "https" : "http" }

  if ENV['REDIS_CACHE_URL'].present?
    cache_servers = ENV['REDIS_CACHE_URL'].split(',')
    config.cache_store = :redis_cache_store, {
      url: cache_servers,
      connect_timeout: 30,
      read_timeout: 0.2,
      write_timeout: 0.2,
      reconnect_attempts: 2
    }
  else
    config.cache_store = :memory_store
  end

  config.active_job.queue_adapter = :sidekiq

  if ENV['SENDGRID_API_KEY'].present?
    config.action_mailer.smtp_settings = {
      user_name: 'apikey',
      password: ENV['SENDGRID_API_KEY'],
      domain: ENV.fetch('SENDGRID_DOMAIN', mailer_host),
      address: 'smtp.sendgrid.net',
      port: 587,
      authentication: :plain,
      enable_starttls_auto: true
    }
  end

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]
end