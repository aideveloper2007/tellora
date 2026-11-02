module Spree
  module ProductDecorator
    def self.prepended(base)
      base.scope :enquiry_mode, -> { where(enquiry_mode: true) }
      base.scope :add_to_cart_mode, -> { where(enquiry_mode: false) }
    end
    
    def enquiry_url
      if custom_enquiry_url.present?
        custom_enquiry_url
      else
        # Default enquiry page - you can customize this route
        Rails.application.routes.url_helpers.enquiry_path(product_id: id) rescue '/enquiry'
      end
    end
    
    def enquiry_mode?
      enquiry_mode == true
    end
    
    # Add the new method
    def description_display_type
      read_attribute(:description_display_type) || 'list'
    end
    
    def description_display_type=(value)
      write_attribute(:description_display_type, value)
    end
  end
end

Spree::Product.prepend Spree::ProductDecorator