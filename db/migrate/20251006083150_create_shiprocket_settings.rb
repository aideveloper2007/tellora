class CreateShiprocketSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :shiprocket_settings do |t|
      t.string :email
      t.string :password

      t.timestamps
    end
  end
end