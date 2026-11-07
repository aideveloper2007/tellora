# frozen_string_literal: true

# "Move my store" by screenshots: the folder (storage/imports/<import_dir>) that holds
# the owner's uploaded screenshots and the design rebuilt from them.
class AddImportDirToStoreBuilds < ActiveRecord::Migration[8.0]
  def change
    add_column :store_builds, :import_dir, :string unless column_exists?(:store_builds, :import_dir)
  end
end
