module Spree
  module OrderDecorator
    def self.prepended(base)
      # Use state_machine block syntax
      base.state_machine do
        after_transition to: :complete, do: :send_to_shiprocket
      end
    end
    
    def send_to_shiprocket
      # Calculate total weight and average dimensions from all line items
      total_weight = line_items.sum { |item| item.variant.weight.to_f * item.quantity }
      avg_length   = line_items.average(:quantity).to_f # fallback if needed
      first_variant = line_items.first.variant
      store = Spree::Store.default
      
      payload = {
        order_id: number,
        order_date: completed_at || Time.current.strftime("%Y-%m-%d %H:%M"),
        pickup_location: "dinesh o"|| "sam"||"home",
        billing_customer_name: bill_address.firstname,
        billing_last_name: bill_address.lastname,
        billing_address: bill_address.address1,
        billing_address_2: bill_address.address2,
        billing_city: bill_address.city,
        billing_pincode: bill_address.zipcode,
        billing_state: bill_address.state_text,
        billing_country: bill_address.country.try(:name),
        billing_email: email,
        billing_phone: bill_address.phone,
        shipping_is_billing: true,
        order_items: line_items.map do |item|
          {
            name: item.name,
            sku: item.variant.sku,
            units: item.quantity,
            selling_price: item.price.to_f
          }
        end,
        payment_method: payments.first.try(:payment_method).try(:name) || "Prepaid",
        sub_total: total.to_f,
        length: first_variant.depth.to_f > 0 ? first_variant.depth.to_f : 10,
        breadth: first_variant.width.to_f > 0 ? first_variant.width.to_f : 10,
        height: first_variant.height.to_f > 0 ? first_variant.height.to_f : 10,
        weight: total_weight.positive? ? total_weight : 0.5
      }
      
      ShiprocketService.create_order(payload)
    end
  end
end

::Spree::Order.prepend Spree::OrderDecorator