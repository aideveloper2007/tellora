module Spree
  class CashfreeCheckout < Spree::Base
    belongs_to :order, class_name: 'Spree::Order'
    has_many :payments, as: :source

    validates :cf_payment_id, presence: true
    validates :cf_order_id, presence: true
  end
end