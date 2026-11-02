require 'factory_girl'

FactoryGirl.define do
  factory :ccavenue_payment_gateway, :class => Spree::Gateway::Ccavenue do
    name 'ccavenue'
    environment 'test'
    preferred_merchant_id 'M_ccavenuecust_12345'
    preferred_encryption_key '0987654321'
    preferred_access_code '765865865'
  end
end
