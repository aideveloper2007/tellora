require 'spree_core'
require 'spree_extension'
require 'spree_ccavenue/version'

module SpreeCcavenue
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_ccavenue'
    
    config.generators do |g|
      g.test_framework :rspec
    end
    
    # Load migrations from the gem
    initializer :append_migrations do |app|
      unless app.root.to_s.match root.to_s
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end
    
    def self.activate
      puts "=== CCAVENUE ACTIVATE CALLED ==="
      
      # Load extensions from lib directory (outside Zeitwerk)
      gem_root = File.expand_path('../..', __FILE__)
      
      order_ext = File.join(gem_root, 'lib/extensions/order_extensions.rb')
      payment_ext = File.join(gem_root, 'lib/extensions/payment_extensions.rb')
      
      load(order_ext) if File.exist?(order_ext)
      load(payment_ext) if File.exist?(payment_ext)
      
      # Load controller decorators
      Dir.glob(File.join(gem_root, 'app/controllers/**/*_decorator*.rb')) do |c|
        load(c)
      end
      
      puts "=== CCAVENUE ACTIVATE FINISHED ==="
    end
    
    config.to_prepare(&method(:activate).to_proc)
    
    config.after_initialize do |app|
      activate
      app.config.spree.payment_methods ||= []
      app.config.spree.payment_methods << ::Spree::PaymentMethod::Ccavenue
    end
  end
end