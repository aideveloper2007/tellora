# frozen_string_literal: true

# "Move my store" by screenshots: the owner uploads full-page screenshots of
# their current home page, and Tellora rebuilds that exact design.
#
#   dir = ScreenshotImport.save_uploads(desktop_file, mobile_file)  # => "a1b2c3..." (kept until the build runs)
#   ScreenshotImport.read(build)  # asks the GenAI Theme API for the design, saves it, returns its summary
#   ScreenshotImport.design(build) # the saved design (header/main/footer HTML, CSS, images, ...)
#
# Files live in storage/imports/<dir>/ (shared by the web and Sidekiq containers).
class ScreenshotImport
  ROOT = Rails.root.join('storage', 'imports')
  MAX_BYTES = 20 * 1024 * 1024
  REQUEST_TIMEOUT = 30 * 60 # seconds: Claude builds, the browser renders and compares, up to 4 passes
  SIGNATURES = {
    'png' => "\x89PNG\r\n\x1A\n".b,
    'jpg' => "\xFF\xD8\xFF".b
  }.freeze

  class Invalid < StandardError; end
  class Failed < StandardError; end

  class << self
    # Checks and stores the uploaded screenshots. Returns the folder name.
    def save_uploads(desktop, mobile = nil)
      raise Invalid, 'Upload a full-page screenshot of your home page (desktop)' if desktop.blank?

      dir = SecureRandom.hex(12)
      path = ROOT.join(dir)
      FileUtils.mkdir_p(path)
      File.binwrite(path.join("desktop.#{check!(desktop, 'desktop')}"), bytes_of(desktop))
      File.binwrite(path.join("mobile.#{check!(mobile, 'mobile')}"), bytes_of(mobile)) if mobile.present?
      dir
    end

    def valid_dir?(dir)
      dir.to_s.match?(/\A\h{24}\z/) && Dir.glob(ROOT.join(dir, 'desktop.*')).any?
    end

    # Calls the GenAI Theme API, saves the design next to the screenshots.
    def read(build)
      dir = build.import_dir
      raise Failed, 'the screenshots of your store were not found, please upload them again' unless valid_dir?(dir)

      desktop = Dir.glob(ROOT.join(dir, 'desktop.*')).first
      mobile = Dir.glob(ROOT.join(dir, 'mobile.*')).first
      files = [File.open(desktop, 'rb')]
      files << File.open(mobile, 'rb') if mobile

      body = { desktop: files.first, store_name: build.store_name }
      body[:mobile] = files.second if mobile
      response = HTTParty.post(
        "#{ENV.fetch('GENAI_SERVICE_URL', 'http://localhost:8000')}/api/v1/screenshot-design",
        body: body,
        multipart: true,
        timeout: REQUEST_TIMEOUT
      )
      raise Failed, error_message(response) unless response.success?

      data = response.parsed_response
      raise Failed, 'nothing came back from the design service' unless data.is_a?(Hash) && data['main_html'].present?

      File.write(ROOT.join(dir, 'design.json'), data.to_json)
      data.slice('score', 'passes', 'viewport', 'description')
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise Failed, 'rebuilding the design took too long'
    rescue Errno::ECONNREFUSED
      raise Failed, 'the design service did not respond'
    ensure
      Array(files).each { |f| f.close unless f.closed? }
    end

    def design(build)
      path = ROOT.join(build.import_dir.to_s, 'design.json')
      valid_dir?(build.import_dir) && File.exist?(path) ? JSON.parse(File.read(path)) : nil
    end

    private

    def bytes_of(upload)
      upload.rewind if upload.respond_to?(:rewind)
      upload.read
    end

    # Returns the file extension for a valid image, or raises Invalid
    def check!(upload, label)
      raise Invalid, "The #{label} screenshot is larger than 20 MB" if upload.size > MAX_BYTES

      upload.rewind if upload.respond_to?(:rewind)
      head = upload.read(12).to_s.b
      upload.rewind if upload.respond_to?(:rewind)
      return 'png' if head.start_with?(SIGNATURES['png'])
      return 'jpg' if head.start_with?(SIGNATURES['jpg'])
      return 'webp' if head[0, 4] == 'RIFF' && head[8, 4] == 'WEBP'

      raise Invalid, "The #{label} screenshot must be a PNG, JPG or WEBP image"
    end

    def error_message(response)
      body = response.parsed_response
      detail = body.is_a?(Hash) ? body['detail'] : nil
      message = detail.is_a?(Hash) ? detail.dig('error', 'message') : nil
      message.presence || "the design service answered with error #{response.code}"
    end
  end
end
