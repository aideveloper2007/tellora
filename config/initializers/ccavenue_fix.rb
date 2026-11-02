Rails.application.config.after_initialize do
  # Ensure CCAvenue is in the payment methods list
  unless Rails.application.config.spree.payment_methods.include?(Spree::PaymentMethod::Ccavenue)
    Rails.application.config.spree.payment_methods << Spree::PaymentMethod::Ccavenue
  end
end