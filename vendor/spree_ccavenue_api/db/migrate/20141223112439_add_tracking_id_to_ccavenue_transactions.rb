class AddTrackingIdToCcavenueTransactions < ActiveRecord::Migration[8.0]
  def change
    # Skip when the column is already there (store databases created from schema.rb)
    add_column :spree_ccavenue_transactions, :tracking_id, :string, if_not_exists: true
  end
end