class CreateSpreeCcavenueTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :spree_ccavenue_transactions do |t|
      t.integer :order_id
      t.integer :payment_method_id
      t.string :transaction_number
      t.string :ccavenue_order_number
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency
      t.string :ccavenue_amount
      t.string :state
      t.string :auth_desc
      t.string :checksum
      t.string :card_category
      t.timestamps
    end
  end
end