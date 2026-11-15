# frozen_string_literal: true

# Shiprocket shipping for Tellora stores. Both tables live in the public schema
# (ShiprocketAccount and ShiprocketShipment are Apartment excluded models), so the
# courier webhook can find the right store from its token.
class CreateShiprocketTables < ActiveRecord::Migration[8.0]
  def change
    # One Shiprocket API user per store (the owner's own Shiprocket account)
    create_table :shiprocket_accounts, if_not_exists: true do |t|
      t.bigint   :store_id,           null: false
      t.string   :tenant_code,        null: false
      t.string   :email,              null: false
      t.text     :password_encrypted, null: false   # encrypted with the app's secret key
      t.text     :token                             # login token, renewed automatically
      t.datetime :token_expires_at
      t.string   :pickup_location                   # name of the pickup address in Shiprocket
      t.string   :pickup_postcode
      t.decimal  :fallback_rate, precision: 10, scale: 2, null: false, default: 99 # used when Shiprocket does not answer
      t.string   :webhook_token,      null: false
      t.boolean  :auto_push,          null: false, default: true # send paid / COD orders to Shiprocket automatically
      t.datetime :connected_at
      t.timestamps
    end
    add_index :shiprocket_accounts, :tenant_code, unique: true, if_not_exists: true
    add_index :shiprocket_accounts, :webhook_token, unique: true, if_not_exists: true

    # One row per Spree order sent to Shiprocket
    create_table :shiprocket_shipments, if_not_exists: true do |t|
      t.string   :tenant_code,     null: false
      t.bigint   :spree_order_id,  null: false
      t.string   :order_number,    null: false
      t.bigint   :sr_order_id
      t.bigint   :sr_shipment_id
      t.string   :awb_code
      t.string   :courier_name
      t.bigint   :courier_id
      t.string   :label_url
      t.string   :status,          null: false, default: 'new' # new, awb_assigned, pickup_scheduled, then the courier's status
      t.string   :courier_status                                 # last status from the courier (e.g. IN TRANSIT, DELIVERED)
      t.string   :error
      t.boolean  :cod,             null: false, default: false
      t.jsonb    :last_event,      null: false, default: {}
      t.datetime :pickup_scheduled_at
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :shiprocket_shipments, %i[tenant_code spree_order_id], unique: true, if_not_exists: true
    add_index :shiprocket_shipments, :awb_code, if_not_exists: true
    add_index :shiprocket_shipments, %i[tenant_code order_number], if_not_exists: true
  end
end
