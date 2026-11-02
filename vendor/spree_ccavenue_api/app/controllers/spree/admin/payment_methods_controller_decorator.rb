require 'api_caller'

module Spree
  module Admin
    module PaymentMethodsControllerDecorator
      def new
        super
        @providers ||= Rails.application.config.spree.payment_methods
      end

      def create
        super
        @providers ||= Rails.application.config.spree.payment_methods
      end

      def edit
        super
        @providers ||= Rails.application.config.spree.payment_methods
      end

      def update
        super
        @providers ||= Rails.application.config.spree.payment_methods
      end

      def verify
        payment_method = Spree::PaymentMethod.find(params[:id])
        payment_method.preferred_merchant_id = params[:gateway_ccavenue][:preferred_merchant_id]
        payment_method.preferred_access_code = params[:gateway_ccavenue][:preferred_access_code]
        payment_method.preferred_encryption_key = params[:gateway_ccavenue][:preferred_encryption_key]
        
        respond_to do |format|
          if payment_method_preferred_params_invalid?(payment_method)
            format.html { render plain: 'Verification failed' }
          else
            reason = CcavenueApi::ApiCaller.status(payment_method, nil, nil).reason
            reason = (reason.include?('Providing Reference_No/Order No is mandatory')) ? 'Verified successfully' : reason
            format.html { render plain: reason }
          end
        end
      end

      private

      def payment_method_preferred_params_invalid?(pm)
        pm.preferred_merchant_id.blank? || pm.preferred_access_code.blank? || pm.preferred_encryption_key.blank?
      end

      def ccavenue_gateway?
        params[:payment_method][:type] == 'Spree::PaymentMethod::Ccavenue'
      end
    end
  end
end

Spree::Admin::PaymentMethodsController.prepend(Spree::Admin::PaymentMethodsControllerDecorator)