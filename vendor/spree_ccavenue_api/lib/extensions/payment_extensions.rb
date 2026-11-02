module SpreePaymentDecorator
  extend ActiveSupport::Concern

  def status!
    payment_source.status
  end

  def sync!
    payment_source.sync
  end
end

Spree::Payment.prepend(SpreePaymentDecorator)