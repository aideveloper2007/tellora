# frozen_string_literal: true

module Platform
  # The files of an owner's own design (CSS, images, fonts, scripts, other pages):
  #   GET /tellora/design-files/<version>/<path>
  # Each upload gets a new version, so files can be cached for a long time.
  class DesignFilesController < ActionController::Base
    def show
      path = CustomDesign.file_path(params[:version], params[:path])
      return head(:not_found) unless path

      response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
      response.headers['X-Content-Type-Options'] = 'nosniff'
      send_file path, type: CustomDesign.content_type(path), disposition: 'inline'
    end
  end
end
