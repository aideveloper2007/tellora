module Spree
  module CashFree
    extend ActiveSupport::Concern

    def update_cashfree_checkout
      cashfree_checkout = Spree::CashfreeCheckout.find_or_initialize_by(order_id: order.try(:id))
      cashfree_checkout.update_columns(update_cashfree_response)
    end

    def update_cashfree_response
      {
        cf_payment_id: params['referenceId'],
        cf_order_id: params['orderId'],
        cf_signature: params['signature'],
        payment_status: params['txStatus'],
        payment_mode: params['paymentMode'],
        payment_amount: params['orderAmount'],
        payment_time: params['txTime']
      }
    end
  end
end