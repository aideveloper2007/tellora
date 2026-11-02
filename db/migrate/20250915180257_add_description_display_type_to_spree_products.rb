class AddDescriptionDisplayTypeToSpreeProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :spree_products, :description_display_type, :string
  end
end
