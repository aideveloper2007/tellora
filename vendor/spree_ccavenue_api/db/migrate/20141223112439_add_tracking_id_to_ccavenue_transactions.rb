class AddTrackingIdToCcavenueTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :spree_ccavenue_transactions, :tracking_id, :string
  end
end