module OrderExtensions
  extend ActiveSupport::Concern
  included do
    state_machine.after_transition to: :complete, do: :send_confirmation_email
  end
  
  private
  
  def send_confirmation_email
    return if confirmation_delivered?
    
    Spree::OrderMailer.confirm_email(self).deliver_now
    
    if store.new_order_notifications_email.present?
      Spree::OrderMailer.store_owner_notification_email(self).deliver_now
    end
    
    update_column(:confirmation_delivered, true)
  rescue Net::SMTPFatalError => e
    Rails.logger.error "Email failed for order #{number}: #{e.message}"
  end
end
Spree::Order.include OrderExtensions