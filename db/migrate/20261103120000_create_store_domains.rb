# frozen_string_literal: true

# Custom domains connected by store owners (www.mybrand.com -> their Tellora store).
# Lives in the public schema (StoreDomain is an Apartment excluded model), so one
# table decides which domain belongs to which store, across all stores.
class CreateStoreDomains < ActiveRecord::Migration[8.0]
  def change
    create_table :store_domains, if_not_exists: true do |t|
      t.bigint   :store_id,           null: false
      t.string   :tenant_code,        null: false
      t.string   :host,               null: false   # what the owner entered, normalised: mybrand.com or shop.mybrand.com
      t.boolean  :apex,               null: false, default: false
      t.string   :primary_host,       null: false   # the address visitors end up on: www.mybrand.com or mybrand.com
      t.string   :verification_token, null: false
      t.string   :status,             null: false, default: 'pending'
      t.jsonb    :dns_report,         null: false, default: {}
      t.string   :error
      t.integer  :check_count,        null: false, default: 0
      t.datetime :last_checked_at
      t.datetime :verified_at
      t.datetime :ssl_issued_at
      t.timestamps
    end

    add_index :store_domains, :host, unique: true, if_not_exists: true
    add_index :store_domains, :primary_host, unique: true, if_not_exists: true
    add_index :store_domains, :tenant_code, if_not_exists: true
    add_index :store_domains, :status, if_not_exists: true
  end
end
