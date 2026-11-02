 require 'api_caller'

module Spree
  class CcavenueController < StoreController
    skip_before_action :verify_authenticity_token, only: :callback
    #skip_before_action :verify_authenticity_token, only: :callback
    helper 'spree/orders' # we need this to avoid undefined method truncated_product_description in frontend. Details on: https://coveralls.io/builds/769164
    rescue_from Net::SMTPFatalError, with: :handle_smtp_error
    #ssl_allowed
   #layout false
    def show
      #binding.remote_pry
      @payment_method = Spree::PaymentMethod.find(params[:payment_method_id])
      if @payment_method.nil?
        flash[:error] = "Payment method not found."
        redirect_to spree.root_path and return
      end

      @order = current_order(include_completed: true)
      if @order.nil?
        Rails.logger.error "Order not found for session: #{session[:order_id]}"
        flash[:error] = "Order not found. Please try again."
        redirect_to spree.root_path and return
      end

      unless @order.respond_to?(:has_authorized_ccavenue_transaction?)
        Rails.logger.error "Order does not support CCAvenue transactions."
        flash[:error] = "Order does not support CCAvenue transactions."
        redirect_to spree.root_path and return
      end

      if @order.has_authorized_ccavenue_transaction?
        flash[:error] = "This order already has an authorized CCAvenue transaction."
        render :error and return
      end

      if @order&.has_authorized_ccavenue_transaction?
        flash[:error] = Spree.t('order_number_already_authorized', order_number: @order.number)
        render :error
        return
      end

      @order.cancel_existing_ccavenue_transactions!
      @order.payments.destroy_all
      card = Spree::CreditCard.first
      @order.payments.build(:amount => @order.total, :payment_method_id => @payment_method.id, source: card)
      @transaction = @order.ccavenue_transactions.build(:amount => @order.total,
                                                        :currency => @order.currency.to_s,
                                                        :payment_method_id => @payment_method.id)

      @transaction.transact

      @order.save!
      raise Spree.t('order_not_saved', order: @order.inspect) unless @order.persisted?
      logger.info("Sending order #{@order.number} to CCAvenue via transaction id #{@transaction.id}")
      @bill_address, @ship_address = @order.bill_address, (@order.ship_address || @order.bill_address)
      #render template: "ccavenue/show"
    end

    def callback
      #binding.remote_pry
      @transaction = Spree::Ccavenue::Transaction.find(params[:id])
      raise Spree.t('transaction_not_found', id: params[:id]) unless @transaction
      #binding.remote_pry
      params = decrypt_ccavenue_response_params
      logger.info "Decrypted params from CCAvenue #{params.inspect}"
      @transaction.auth_desc = params['order_status']
      @transaction.card_category = params['card_name']
      @transaction.ccavenue_order_number = params['order_id']
      @transaction.tracking_id = params['tracking_id']
      @transaction.ccavenue_amount = params['amount']
      
      session[:access_token] = @transaction.order.guest_token if @transaction.order.respond_to?(:guest_token)
      session[:order_id] = @transaction.order.id
      
      if @transaction.order.insufficient_stock_lines.present?

        response = @transaction.void
        render Spree.t('refund_failed', reason: response.reason) and return unless response.success?
        update_order_payment_state(@transaction.order)
        redirect_to edit_order_path(@transaction.order), :notice => Spree.t("payment_not_processed")
        return
      end

      if @transaction.next
        handle_successful_transaction
      else
        render 'error'
      end

    end

    private

def handle_successful_transaction
  if @transaction.authorized? # Successful
    session[:order_id] = nil
    flash.notice = Spree.t(:order_processed_successfully)
    
    # Use spree. prefix and order.token directly
    if @transaction.order.user_id.present?
      redirect_to spree.order_path(@transaction.order, checkout_complete: true)
    else
      redirect_to spree.order_path(@transaction.order, checkout_complete: true, token: @transaction.order.token)
    end
  elsif @transaction.rejected?
    flash.notice = "Payment was not approved at the payment gateway. Retry with correct creditcard/netbanking information"
    redirect_to spree.edit_order_path(@transaction.order)
  elsif @transaction.canceled?
    redirect_to spree.edit_order_path(@transaction.order), notice: I18n.t("payment_canceled")
  elsif @transaction.initiated?
    redirect_to spree.edit_order_path(@transaction.order), notice: I18n.t("payment_initiated")
  end
end

    def update_order_payment_state(order)
      order.update_column(:payment_state, 'void')
    end

    def decrypt_ccavenue_response_params
      Rails.logger.info "Received transaction from CCAvenue #{params.inspect}"
      encryption_key = @transaction.payment_method.preferred_encryption_key
      query = AESCrypter.decrypt(params['encResp'], encryption_key)
      Rack::Utils.parse_nested_query(query)
    end


  def handle_smtp_error(exception)
    if exception.message.include?('550') && exception.message.include?('Sender Identity')
      # Get order from params or session
      @order = Spree::Order.find_by(number: params[:order_number]) || current_order
      
      if @order
        @order.update(payment_state: 'paid')
        Spree::OrderMailer.with(
          from: Spree.config.mails_from,
          to: @order.email
        ).confirm_email(@order).deliver_later
        
        flash[:success] = "Order processed successfully"
        redirect_to order_path(@order)
      else
        flash[:error] = "Email not verified"
        redirect_to root_path
      end
    else
      raise exception
    end
  end





  end
end