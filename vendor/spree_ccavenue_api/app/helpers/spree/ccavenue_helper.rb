require 'aes_crypter'

module Spree
  module CcavenueHelper

    def css_class_based_on_order_state(order)
      order.state == 'confirm' ? 'alpha omega grid_24' : 'alpha grid_16'
    end

    def encrypted_request(payment_method, transaction, order, redirect_url, encryption_key)
      params = request_params(payment_method, transaction, order, redirect_url)
      AESCrypter.encrypt(params, encryption_key)
    end

    def request_params(payment_method, transaction, order, redirect_url)
      bill_address = order.bill_address || order.ship_address
      ship_address = order.ship_address || order.bill_address
      
      # If still no addresses, raise a helpful error
      raise "Order #{order.number} is missing billing and shipping addresses" unless bill_address && ship_address
      
      "merchant_id=#{payment_method.preferred_merchant_id}&order_id=#{transaction.gateway_order_number}&amount=#{order.total.to_s}&currency=#{order.currency.to_s}&redirect_url=#{redirect_url}&cancel_url=&language=EN&billing_name=#{bill_address.full_name}&billing_address=#{bill_address.address1}&billing_city=#{bill_address.city}&billing_state=#{bill_address.state.try(:name) || bill_address.state_name}&billing_zip=#{bill_address.zipcode}&billing_country=#{bill_address.country.name}&billing_tel=#{bill_address.phone}&billing_email=#{order.email}&delivery_name=#{ship_address.full_name}&delivery_address=#{ship_address.address1}&delivery_city=#{ship_address.city}&delivery_state=#{ship_address.state.try(:name) || ship_address.state_name}&delivery_zip=#{ship_address.zipcode}&delivery_country=#{ship_address.country.name}&delivery_tel=#{ship_address.phone}&merchant_param1=&merchant_param2=&merchant_param3=&merchant_param4=&merchant_param5=&promo_code=#{order.coupon_code}"
    end
  end
end