module Apartment
  SchemaNotFound = Class.new(StandardError) unless defined?(Apartment::SchemaNotFound)
  TenantNotFound = Class.new(StandardError) unless defined?(Apartment::TenantNotFound)
end
