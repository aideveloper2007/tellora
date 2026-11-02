source "https://rubygems.org"
ruby '3.2.4'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'rails', '~> 8.0.0'
# Use pg as the database for Active Record
gem "pg", "~> 1.1"
# pgvector for vector embeddings
gem 'pgvector'
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem 'mini_racer', platforms: :ruby
gem "redis", ">= 4.0.1"
gem 'ros-apartment', require: 'apartment'
gem 'acts_as_tenant'
gem "tzinfo-data", platforms: %i[windows jruby]
gem "bootsnap", require: false
gem "image_processing", "~> 1.13"
gem 'bcrypt', '~> 3.1.7'
gem 'listen'

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem 'brakeman'
  gem 'dotenv-rails', '~> 3.1'
  gem 'rubocop', '~> 1.23'
  gem 'rubocop-performance'
  gem 'rubocop-rails'
  gem 'selenium-webdriver', '~> 4.10.0'
  gem 'pry'
  gem 'pry-remote'
end

group :development do
  gem "foreman"
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  # Preview emails in the browser [https://github.com/plataformatec/letter_opener]
  gem "letter_opener"
  # LSP support for Ruby
  gem 'solargraph'
  gem 'solargraph-rails'
  gem 'ruby-lsp'
  gem 'ruby-lsp-rails'
end

group :test do
  gem 'capybara', '~> 3.39'
  gem 'capybara-screenshot', '~> 1.0'
  gem 'email_spec'
  gem 'factory_bot'
  gem 'factory_bot_rails'
  gem 'database_cleaner'
  gem 'rspec-activemodel-mocks', '~> 1.0'
  gem 'rspec-rails', '~> 8.0'
  gem 'rspec-retry'
  gem 'rspec_junit_formatter'
  gem 'rubocop-rspec'
  gem 'jsonapi-rspec'
  gem 'simplecov'
  gem 'webmock', '~> 3.7', require: false
  gem 'timecop'
  gem 'rails-controller-testing'
  gem 'webdrivers', '~> 5.0'
end

gem 'sidekiq'
gem "devise"

# Sentry for error/performance monitoring
gem 'sentry-ruby'
gem 'sentry-rails'
gem 'sentry-sidekiq'

# Spree gems
spree_opts = '~> 5.1'
gem "spree", spree_opts
gem "spree_emails", spree_opts
gem "spree_sample", spree_opts
gem "spree_admin", spree_opts
gem "spree_storefront", spree_opts
gem "spree_i18n"
gem "spree_stripe", '~> 1.2'
gem "spree_google_analytics", "~> 1.0"
gem "spree_klaviyo", "~> 1.0"
gem "spree_paypal_checkout", "~> 0.7"

# Custom Spree extensions
gem 'spree_import_products', path: 'vendor/spree_import_products'
gem 'spree_razorpay', git: 'https://github.com/spree-edge/spree_razorpay.git'
gem 'spree_ccavenue', path: 'vendor/spree_ccavenue_api'
gem 'spree_cashfree', path: 'vendor/spree_cashfree'  # Added Cashfree extension

# PDF generation
gem 'prawn'
gem 'prawn-table'
gem 'prawn-rails'

gem 'httparty'
gem 'json'
