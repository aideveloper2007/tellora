require 'spree_core'
require 'spree_extension'

module SpreeImportProducts
  # Define Configuration class for asset precompilation
  class Configuration
    def initialize
    end
  end
end

require 'spree_import_products/engine'
require 'spree_import_products/version'