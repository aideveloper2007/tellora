# frozen_string_literal: true

# Background job: fills a newly themed store with AI-generated sample products.
# Runs in Sidekiq so the theme "Apply" button returns immediately.
class SampleProductsJob
  include Sidekiq::Job
  sidekiq_options retry: 2

  def perform(tenant, store_id, store_type)
    Apartment::Tenant.switch(tenant) do
      store = Spree::Store.find_by(id: store_id) || Spree::Store.default
      Spree::Store.current = store if Spree::Store.respond_to?(:current=)

      SampleProductsGenerator.new(store: store, store_type: store_type).call
    end
  end
end
