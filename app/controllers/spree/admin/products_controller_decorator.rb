module Spree
  module Admin
    module ProductsControllerDecorator
      def import
        if request.get?
          @products = ::Spree::Product.new
          render :import
        elsif request.post?
          Rails.logger.info "=== DEBUG PARAMS ==="
          Rails.logger.info "All params: #{params.inspect}"
          Rails.logger.info "===================="
          
          file = nil
          if params[:spree_product] && params[:spree_product][:file]
            file = params[:spree_product][:file]
          elsif params[:product] && params[:product][:file]
            file = params[:product][:file]
          elsif params[:file]
            file = params[:file]
          end
          
          if file.nil?
            flash[:error] = "No file uploaded. Please select a file."
            @products = ::Spree::Product.new
            render :import and return
          end
          
          begin
            file_path = file.path
            import_log = Object.new
            import_log.define_singleton_method(:started_by_email) { spree_current_user.email }
            import_log.define_singleton_method(:state) { 'created' }
            import_log.define_singleton_method(:store_id) { current_store.id }
            import_log.define_singleton_method(:success_row_count) { 0 }
            import_log.define_singleton_method(:error_row_count) { 0 }
            import_log.define_singleton_method(:error_details) { {} }
            import_log.define_singleton_method(:update_columns) { |attrs| }
            import_log.define_singleton_method(:update_column) { |col, val| }
            import_log.define_singleton_method(:increment!) { |col| }
            import_log.define_singleton_method(:save) { }
            ProductsImport::Import.new(file_path, spree_current_user, import_log, current_store).perform_import
            flash[:success] = "Product import successful."
            redirect_to admin_products_path
          rescue => e
            Rails.logger.error "Import error: #{e.message}"
            flash[:error] = "Import failed: #{e.message}"
            @products = ::Spree::Product.new
            render :import
          end
        end
      end
      
      # Add both enquiry and description display fields to permitted parameters
      private
      def permitted_product_attributes
        super + [:enquiry_mode, :custom_enquiry_url, :description_display_type]
      end
    end
  end
end

Spree::Admin::ProductsController.prepend Spree::Admin::ProductsControllerDecorator