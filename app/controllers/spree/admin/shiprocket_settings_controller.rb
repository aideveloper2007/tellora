require 'net/http'
require 'uri'
require 'json'

module Spree
  module Admin
    class ShiprocketSettingsController < Spree::Admin::BaseController
      def edit
        @shiprocket_setting = ShiprocketSetting.first_or_initialize
      end

      def update
        @shiprocket_setting = ShiprocketSetting.first_or_initialize
        if @shiprocket_setting.update!(shiprocket_setting_params)
          flash[:success] = 'Shiprocket settings updated successfully'
          redirect_to edit_admin_shiprocket_settings_path
        else
          flash[:error] = 'Unable to update settings'
          render :edit
        end
      end
      

      private

      def shiprocket_setting_params
        params.require(:shiprocket_setting).permit(:email, :password)
      end
    end
  end
end