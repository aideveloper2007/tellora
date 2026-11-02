module SpreeCashfree
  module Spree
    module OrderDecorator
      def cashfree_payment(payment_params, payment_method)
        payments.create!(
          source: ::Spree::CashfreeCheckout.create!(
            order_id: id,
            cf_payment_id: payment_params['referenceId'],
            cf_order_id: payment_params['orderId'],
            cf_signature: payment_params['signature'],
            payment_status: payment_params['txStatus'],
            payment_mode: payment_params['paymentMode'],
            payment_amount: payment_params['orderAmount'],
            payment_time: payment_params['txTime']
          ),
          payment_method: payment_method,
          amount: total,
          response_code: payment_params['txStatus']
        )
      end

      ::Spree::Order.prepend SpreeCashfree::Spree::OrderDecorator
    end
  end
end