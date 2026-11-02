# frozen_string_literal: true

# Stores built from the landing page stay private ("Opening soon") until the owner presses Publish.
class AddPublishingToStoreBuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :store_builds, :published_at, :datetime
    add_column :store_builds, :pending_theme_api_id, :string # design change in progress from the builder
    add_index  :store_builds, :tenant_code
  end
end
