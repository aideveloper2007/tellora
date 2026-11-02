module Spree
  module PaymentMethodDecorator
    def payment_icon_name
      # Fallback if type is nil
      klass = self.class.name || type
      klass.to_s.demodulize.underscore
    end
  end
end

::Spree::PaymentMethod.prepend(::Spree::PaymentMethodDecorator)