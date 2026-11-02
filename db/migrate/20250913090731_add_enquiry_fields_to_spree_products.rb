class AddEnquiryFieldsToSpreeProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :spree_products, :enquiry_mode, :boolean
    add_column :spree_products, :custom_enquiry_url, :string
  end
end
