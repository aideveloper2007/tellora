# app/decorators/controllers/spree/admin/payment_methods_controller_decorator.rb
module Spree
  module Admin
    module PaymentMethodsControllerDecorator
      def self.prepended(base)
        base.before_action :permit_upi_manual_qr, only: [:create, :update]
      end

      private

      def permit_upi_manual_qr
        return unless params[:payment_method].present?

        if params[:payment_method][:type] == "PaymentMethod::UpiManualPayment"
          params[:payment_method] = params[:payment_method].permit(
            :name, :display_on, :active, :preferred_upi_id, :qr_code
          )
        end
      end
    end
  end
end

Spree::Admin::PaymentMethodsController.prepend Spree::Admin::PaymentMethodsControllerDecorator