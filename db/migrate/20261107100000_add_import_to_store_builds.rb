# frozen_string_literal: true

# "Move my store": a store build can start from the owner's existing online store.
#   source_url          the store they are moving from (domain ownership checked by DNS)
#   source_verified_at  when the DNS ownership check passed
#   brand               what Tellora read from it: logo, colours, fonts, page plan, photos
class AddImportToStoreBuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :store_builds, :source_url, :string unless column_exists?(:store_builds, :source_url)
    add_column :store_builds, :source_verified_at, :datetime unless column_exists?(:store_builds, :source_verified_at)
    add_column :store_builds, :brand, :jsonb unless column_exists?(:store_builds, :brand)
  end
end
