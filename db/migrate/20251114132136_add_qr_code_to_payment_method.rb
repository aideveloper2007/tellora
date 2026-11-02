class AddQrCodeToPaymentMethod < ActiveRecord::Migration[8.0]
  def change
    add_column :spree_payment_methods, :qr_code, :string
  end
end