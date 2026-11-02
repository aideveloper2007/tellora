module Spree
  module PaymentDecorator
    def after_completed
      super

      # This happens ONLY when payment becomes "PAID"
      if order.state != 'complete'
        order.update!(
          state: 'complete',
          completed_at: Time.current
        )
      end
    end
  end
end

Spree::Payment.prepend Spree::PaymentDecorator