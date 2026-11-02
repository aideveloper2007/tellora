module SpreeCashfree
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root(File.expand_path(File.dirname(__FILE__)))

      class_option :migrate, type: :boolean, default: true

      def add_javascripts
        # Check if the traditional vendor path exists
        if File.exist?('vendor/assets/javascripts/spree/frontend/all.js')
          append_file 'vendor/assets/javascripts/spree/frontend/all.js', "//= require spree/frontend/spree_cashfree\n"
          append_file 'vendor/assets/javascripts/spree/frontend/all.js', "//= require spree/frontend/process_cashfree\n"
        else
          # For newer Spree versions, check app/assets
          if File.exist?('app/assets/javascripts/spree/frontend/all.js')
            append_file 'app/assets/javascripts/spree/frontend/all.js', "//= require spree/frontend/spree_cashfree\n"
            append_file 'app/assets/javascripts/spree/frontend/all.js', "//= require spree/frontend/process_cashfree\n"
          else
            say "JavaScript files need to be manually included in your asset pipeline."
            say "Add these lines to your frontend JavaScript manifest:"
            say "//= require spree/frontend/spree_cashfree"
            say "//= require spree/frontend/process_cashfree"
          end
        end
      end

      def add_migrations
        run 'bundle exec rake railties:install:migrations FROM=spree_cashfree'
      end

      def run_migrations
        run_migrations = options[:migrate] || ['', 'y', 'Y'].include?(ask('Would you like to run the migrations now? [Y/n]'))
        if run_migrations
          run 'bundle exec rails db:migrate'
        else
          puts 'Skipping rails db:migrate, don\'t forget to run it!'
        end
      end
    end
  end
end