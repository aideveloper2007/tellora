module Spree
  # Create the missing class that the gem expects
  class PrintInvoiceSetting < Spree::Preferences::Configuration
    preference :logo_path, :string, default: ''
    preference :store_pdf, :boolean, default: false
    preference :storage_path, :string, default: 'pdfs/orders'
    preference :next_number, :integer, default: 1000
    preference :logo_scale, :float, default: 0.75
    preference :footer_left, :string, default: ''
    preference :footer_right, :string, default: ''
    preference :return_message, :string, default: 'Thank you for shopping with us.'
  end
end