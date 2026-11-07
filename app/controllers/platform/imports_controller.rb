# frozen_string_literal: true

module Platform
  # "Move my store": the owner uploads full-page screenshots of their current
  # home page and creates their account. The build rebuilds that exact design
  # (ScreenshotImport + MirrorDesign) on their new Tellora subdomain. They connect
  # their own domain later, from the Domain screen, once they are happy with it.
  #
  # Kept in the session until the account is created:
  #   session[:store_import] = { 'dir' }   (storage/imports/<dir> holds the screenshots)
  class ImportsController < BaseController
    # GET /move
    def new; end

    # POST /move
    def create
      unless params[:rights] == '1'
        raise ScreenshotImport::Invalid, 'Please confirm that this is your design (or that you have the right to use it)'
      end

      dir = ScreenshotImport.save_uploads(params[:desktop], params[:mobile].presence)
      session[:store_import] = { 'dir' => dir }
      session[:store_prompt] = 'Moving my store to Tellora (design rebuilt from my screenshots)'
      redirect_to platform_signup_path
    rescue ScreenshotImport::Invalid => e
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    # The store being moved in this session (used by StoreBuildsController), or nil
    def self.pending(session)
      import = session[:store_import]
      import.is_a?(Hash) && ScreenshotImport.valid_dir?(import['dir']) ? import : nil
    end
  end
end
