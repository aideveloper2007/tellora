class AddTenantFieldsToSpreeStores < ActiveRecord::Migration[7.1]
  def change
    add_column :spree_stores, :subdomain, :string unless column_exists?(:spree_stores, :subdomain)
    unless index_exists?(:spree_stores, :subdomain)
      add_index :spree_stores, :subdomain, unique: true
    end
    unless index_exists?(:spree_stores, :code)
      add_index :spree_stores, :code, unique: true
    end
  end
end
