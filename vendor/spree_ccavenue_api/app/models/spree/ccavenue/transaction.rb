module Spree
  class Ccavenue::Transaction < ActiveRecord::Base
    after_initialize :custom_initialize_from_admin
    belongs_to :order, :class_name => 'Spree::Order'
    belongs_to :payment_method, :class_name => 'Spree::PaymentMethod::Ccavenue'
    has_many :payments, :as => :source

    def void
      raise ArgumentError.new( Spree.t('missing_tracking_id') ) unless tracking_id

      Rails.logger.info "Initiating cancel API call for order: #{order.id} tracking_id: #{tracking_id}"
      response = CcavenueApi::ApiCaller.cancel(order, payment_method, tracking_id)
      Rails.logger.info "Received following API cancel response: #{response.inspect} for order ID: #{order.id} tracking id: #{tracking_id}"
      return response if response.success? # cancel command succeeded

      Rails.logger.info "Initiating refund API call for order: #{order.id} tracking_id: #{tracking_id}"
      response = CcavenueApi::ApiCaller.refund(order, payment_method, tracking_id)
      Rails.logger.info "Received following API refund response: #{response.inspect} for order ID: #{order.id} tracking id: #{tracking_id}"
      response
    end

    def status
      Rails.logger.info "Initiating status API call for order: #{order.id} tracking_id: #{tracking_id}"
      response = CcavenueApi::ApiCaller.status(payment_method, order, tracking_id)
      Rails.logger.info "Received following API status response: #{response.inspect} for order ID: #{order.id} tracking id: #{tracking_id}"
      response
    end

    def sync
      order_status = status.order_status
      payment_state = case order_status.downcase
                        when 'success'
                          'completed'
                        when 'canceled'
                          'pending'
                        when 'shipped'
                          'completed'
                        when 'refund'
                          'void'
                        else
                          raise ArgumentError.new("Unsupported order status: #{order_status}")
                      end

      order.update_column(:payment_state, payment_state)
      # TODO: decrement stock quantity accordingly
    end

    def decrement_stock_quantity

    end

    state_machine :initial => :created, :use_transactions => false do
      before_transition :to => :sent, :do => :initialize_state!
      event :transact do
        transition :created => :sent
      end

      event :next do
        transition :sent => :canceled, :if => lambda { |txn| txn.auth_desc == 'Aborted' }
        transition [:sent, :batch] => :authorized, :if => lambda { |txn| txn.auth_desc == 'Success' }
        transition [:sent, :batch] => :rejected, :if => lambda { |txn| txn.auth_desc == 'Failure' }
        transition [:sent, :batch] => :initiated, :if => lambda { |txn| txn.auth_desc == 'initiated' }
      end
      after_transition :to => :authorized, :do => :payment_authorized

      event :cancel do
        transition all - [:authorized] => :canceled
      end
    end

    def payment_authorized
      payment = order.payments.where(:payment_method_id => self.payment_method.id).first
      payment.update :source => self, :payment_method_id => self.payment_method.id
      payment.complete
      order.updater.update_payment_state  # ADD THIS
      order.next
      order.save
    end

    def initialize_state!
      if order.confirmation_required? && !order.confirm?
        raise Spree.t('order_not_in_confirm_state')
      end
      this = self
      previous = order.ccavenue_transactions.reject { |t| t == this }
      previous.each { |p| p.cancel! }
      generate_transaction_number!
    end

    def gateway_order_number
      #order.number + transaction_number
      order.number #+ transaction_number
    end

    def generate_transaction_number!
      record = true
      while record
        random = "#{Array.new(4) { rand(4) }.join}"
        record = Spree::Ccavenue::Transaction.where(order_id: self.order.id, transaction_number: random).first
      end
      self.transaction_number = random
    end

    def custom_initialize_from_admin
      if self.attributes && self.attributes['from_admin']
        self.attributes.except!('from_admin')
        self.amount = self.order.amount
        self.transact
        self.ccavenue_amount = self.amount.to_s
        self.next
      end
    end

  end
end
