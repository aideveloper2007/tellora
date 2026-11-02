# frozen_string_literal: true

# One row per "Build my store" request from the platform landing page.
# Lives in the public schema (StoreBuild is an Apartment excluded model).
class CreateStoreBuilds < ActiveRecord::Migration[8.0]
  def change
    create_table :store_builds do |t|
      t.string   :token, null: false
      t.string   :status, null: false, default: 'queued' # queued | running | done | failed
      t.string   :completed_step                         # last finished step (see StoreBuild::STEPS)
      t.text     :error

      t.text     :prompt, null: false
      t.string   :store_name, null: false
      t.string   :subdomain, null: false
      t.string   :currency, null: false, default: 'USD'
      t.string   :email, null: false
      t.string   :encrypted_password, null: false        # Devise digest, never the plain password
      t.string   :store_url
      t.string   :ip

      t.string   :tenant_code
      t.bigint   :store_id
      t.bigint   :admin_user_id
      t.string   :theme_api_id

      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :handoff_used_at
      t.timestamps
    end

    add_index :store_builds, :token, unique: true
    add_index :store_builds, :subdomain
    add_index :store_builds, [:ip, :created_at]
  end
end
