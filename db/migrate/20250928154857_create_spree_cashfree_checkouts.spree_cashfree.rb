# This migration comes from spree_cashfree (originally 20240928000001)
class CreateSpreeCashfreeCheckouts < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_cashfree_checkouts do |t|
      t.string :order_id
      t.string :cf_payment_id
      t.string :cf_order_id
      t.string :cf_signature
      t.string :payment_status
      t.string :payment_mode
      t.decimal :payment_amount, precision: 10, scale: 2
      t.string :payment_time
      t.string :bank_reference
      t.string :payment_group

      t.timestamps
    end

    add_index :spree_cashfree_checkouts, :order_id
    add_index :spree_cashfree_checkouts, :cf_payment_id
  end
end