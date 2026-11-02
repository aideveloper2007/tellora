# config/initializers/spree_print_invoice_fonts.rb
Spree::PrintInvoiceSetting.class_eval do
  mattr_accessor :additional_fonts
end

# Now you can safely assign
Spree::PrintInvoiceSetting.additional_fonts = {
  "Helvetica" => {
    normal: Rails.root.join("app/assets/fonts/Helvetica.ttf").to_s,
    bold:   Rails.root.join("app/assets/fonts/Helvetica-Bold.ttf").to_s
  }
}