# frozen_string_literal: true

require 'nokogiri'

# The owner's own design ("Upload my HTML files"): their designer's HTML, CSS, images, fonts
# and scripts, used exactly as they are for the store's home page.
#
#   CustomDesign.install!(store, theme, uploaded_file)  # ZIP or .html; raises CustomDesign::Invalid
#   CustomDesign.for(theme)                             # the installed design, or nil
#   CustomDesign.render(design, products)               # home page HTML with real products
#   CustomDesign.remove!(theme)                         # back to Tellora designs
#
# The GenAI Theme API unpacks and checks the upload and marks the shop parts (product grid,
# cart / account / search / logo links). Here the files are stored, the page's file links are
# pointed at /tellora/design-files/<version>/..., and the product grid becomes a template.
# The design itself is never changed.
#
# Files: storage/designs/<tenant>/<version>/ (shared by the web and Sidekiq containers).
class CustomDesign
  ROOT = Rails.root.join('storage', 'designs')
  FILES_PATH = '/tellora/design-files'
  HOME_FILE = '__tellora_home.html'
  VERSION_FORMAT = /\A\d{14}-\h{8}\z/
  MAX_UPLOAD = 60 * 1024 * 1024
  REQUEST_TIMEOUT = 5 * 60 # seconds

  # Scripts from these hosts are kept (common libraries); scripts from any other site are removed
  SCRIPT_HOSTS = %w[
    cdn.jsdelivr.net cdnjs.cloudflare.com unpkg.com code.jquery.com ajax.googleapis.com
    cdn.tailwindcss.com stackpath.bootstrapcdn.com maxcdn.bootstrapcdn.com use.fontawesome.com
    kit.fontawesome.com cdn.skypack.dev esm.sh ga.jspm.io
  ].freeze

  URL_ATTRIBUTES = %w[src href poster data-src data-background data-bg].freeze
  SRCSET_ATTRIBUTES = %w[srcset data-srcset].freeze

  class Invalid < StandardError; end

  class << self
    def install!(store, theme, upload)
      raise Invalid, 'Choose a .zip file of your site, or a single .html file' if upload.blank?
      raise Invalid, 'The file is larger than 60 MB' if upload.size > MAX_UPLOAD

      package = read_package(upload)
      tenant = Apartment::Tenant.current
      version = "#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
      dir = ROOT.join(tenant, version)

      files = write_files(dir, package['files'])
      index = package['index'].to_s
      raise Invalid, 'The home page was not found in the upload' unless files.include?(index)

      page_map = package['map'].is_a?(Hash) ? package['map'] : {}
      html, details = prepare(File.read(dir.join(index), encoding: 'UTF-8').scrub(''), index, version, page_map)
      File.write(dir.join(HOME_FILE), html)

      save_preferences(theme, 'version' => version, 'index' => index,
                              'sale_label' => details[:sale_label].to_s, 'products' => details[:products])
      MirrorDesign.remove!(store, theme)
      remove_old_versions(tenant, keep: version)
      store.touch
      details
    end

    def for(theme)
      design = (theme&.preferences || {}).to_h['custom']
      return nil unless design.is_a?(Hash) && design['version'].to_s.match?(VERSION_FORMAT)
      return nil unless File.exist?(ROOT.join(Apartment::Tenant.current, design['version'], HOME_FILE))

      design
    end

    # products: [{ name:, price:, compare_price:, image:, url: }]
    def render(design, products)
      html = File.read(ROOT.join(Apartment::Tenant.current, design['version'], HOME_FILE), encoding: 'UTF-8')
      count = html[/data-tellora-products="(\d+)"/, 1].to_i
      sale_label = design['sale_label'].presence || 'Sale'
      html.sub(%r{<!--tellora-card-->(.*?)<!--/tellora-card-->}m) do
        card = Regexp.last_match(1)
        products.first([count, 1].max).map do |product|
          values = product.merge(sale_label: product[:compare_price].present? ? sale_label : '')
          card.gsub(/\{\{(name|price|compare_price|sale_label|image|url)\}\}/) do
            ERB::Util.html_escape(values[Regexp.last_match(1).to_sym].to_s)
          end
        end.join
      end
    end

    def remove!(theme)
      return unless theme && (theme.preferences || {}).to_h.key?('custom')

      prefs = (theme.preferences || {}).to_h.reject { |k, _| k.to_s == 'custom' }
      theme.update_column(:preferences, prefs)
      FileUtils.rm_rf(ROOT.join(Apartment::Tenant.current))
    end

    # The file behind /tellora/design-files/<version>/<path>, or nil
    def file_path(version, path)
      return nil unless version.to_s.match?(VERSION_FORMAT)

      root = ROOT.join(Apartment::Tenant.current, version).to_s
      full = File.expand_path(path.to_s, root)
      full.start_with?("#{root}/") && File.file?(full) && File.basename(full) != HOME_FILE ? full : nil
    end

    def content_type(path)
      {
        '.woff2' => 'font/woff2', '.woff' => 'font/woff', '.ttf' => 'font/ttf', '.otf' => 'font/otf',
        '.js' => 'text/javascript', '.mjs' => 'text/javascript', '.svg' => 'image/svg+xml',
        '.webp' => 'image/webp', '.avif' => 'image/avif', '.map' => 'application/json'
      }[File.extname(path).downcase] || Rack::Mime.mime_type(File.extname(path), 'application/octet-stream')
    end

    private

    # Sends the upload to the GenAI Theme API (with its real file name, so .html vs .zip is known)
    def read_package(upload)
      name = File.basename(upload.original_filename.to_s).gsub(/[^\w.\-]/, '_').presence || 'site.zip'
      Dir.mktmpdir do |tmp|
        copy = File.join(tmp, name)
        FileUtils.cp(upload.respond_to?(:tempfile) ? upload.tempfile.path : upload.path, copy)
        File.open(copy, 'rb') do |file|
          response = HTTParty.post("#{ENV.fetch('GENAI_SERVICE_URL', 'http://localhost:8000')}/api/v1/design-package",
                                   body: { file: file }, multipart: true, timeout: REQUEST_TIMEOUT)
          body = response.parsed_response
          unless response.success? && body.is_a?(Hash) && body['files'].is_a?(Array)
            detail = body.is_a?(Hash) && body['detail'].is_a?(Hash) ? body['detail'].dig('error', 'message') : nil
            raise Invalid, detail.presence || "Your design could not be read (error #{response.code})"
          end
          body
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise Invalid, 'Reading your design took too long. Please try again.'
    rescue Errno::ECONNREFUSED
      raise Invalid, 'The design service did not respond. Please try again.'
    end

    def write_files(dir, files)
      FileUtils.mkdir_p(dir)
      root = dir.to_s
      Array(files).filter_map do |file|
        path = file['path'].to_s
        full = File.expand_path(path, root)
        next unless full.start_with?("#{root}/") && File.basename(full) != HOME_FILE

        FileUtils.mkdir_p(File.dirname(full))
        File.binwrite(full, Base64.decode64(file['data'].to_s))
        path
      end
    end

    def remove_old_versions(tenant, keep:)
      Dir.glob(ROOT.join(tenant, '*')).each do |path|
        FileUtils.rm_rf(path) unless File.basename(path) == keep
      end
    end

    def save_preferences(theme, values)
      prefs = (theme.preferences || {}).to_h.reject { |k, _| k.to_s == 'custom' }
      plain = values.to_h { |k, v| [String.new(k), v.is_a?(String) ? String.new(v) : v] }
      theme.update_column(:preferences, prefs.merge('custom' => plain))
    end

    # ---- preparing the page ------------------------------------------------------

    def prepare(html, index, version, page_map)
      doc = Nokogiri::HTML5(html)
      base = File.dirname(index)
      base = '' if base == '.'

      doc.css('base').each(&:remove)
      remove_foreign_scripts(doc)
      rewrite_urls(doc, base, version)
      link_home(doc, index, version)
      link_shop(doc, page_map)
      details = template_products(doc, page_map)

      head = doc.at_css('head') || doc.root
      head&.add_child('<style>[data-tellora-empty]:empty{display:none!important}</style>')
      [doc.to_html, details]
    end

    def remove_foreign_scripts(doc)
      doc.css('script[src]').each do |script|
        src = script['src'].to_s.strip
        next unless src.match?(%r{\A(https?:)?//}i)

        host = URI.parse(src.start_with?('//') ? "https:#{src}" : src).host.to_s.downcase
        script.remove unless SCRIPT_HOSTS.include?(host)
      rescue URI::InvalidURIError
        script.remove
      end
    end

    def rewrite_urls(doc, base, version)
      doc.css('*').each do |node|
        URL_ATTRIBUTES.each do |attr|
          next unless node[attr]
          next if attr == 'href' && !%w[a link area].include?(node.name)

          node[attr] = file_url(node[attr], base, version)
        end
        SRCSET_ATTRIBUTES.each do |attr|
          next unless node[attr]

          node[attr] = node[attr].split(',').map do |part|
            url, size = part.strip.split(/\s+/, 2)
            [file_url(url.to_s, base, version), size].compact.join(' ')
          end.join(', ')
        end
        node['style'] = css_urls(node['style'], base, version) if node['style']
      end
      doc.css('style').each { |style| style.content = css_urls(style.content, base, version) }
    end

    # Links to the design's own home page (or to "/") open the store's home page
    def link_home(doc, index, version)
      home = ["#{FILES_PATH}/#{version}/", "#{FILES_PATH}/#{version}/#{index}"]
      doc.css('a[href]').each do |link|
        path = link['href'].to_s.split(/(?=[?#])/, 2).first.to_s
        link['href'] = '/' if home.include?(path)
      end
    end

    # A link from the page to one of its own files -> its URL in the store
    def file_url(url, base, version)
      value = url.to_s.strip
      return value if value.empty? || value.start_with?('#')
      return '#' if value.match?(/\Ajavascript:/i)
      return value if value.match?(%r{\A([a-z][a-z0-9+.\-]*:|//)}i) # http:, https:, data:, mailto:, tel:, //host

      path, rest = value.split(/(?=[?#])/, 2)
      joined = path.start_with?('/') ? path.delete_prefix('/') : [base, path].reject(&:empty?).join('/')
      parts = []
      joined.split('/').each do |part|
        next if part.empty? || part == '.'

        part == '..' ? parts.pop : parts << part
      end
      "#{FILES_PATH}/#{version}/#{parts.join('/')}#{rest}"
    end

    def css_urls(css, base, version)
      css.to_s.gsub(/url\(\s*(['"]?)([^'")]+)\1\s*\)/i) do
        "url(#{Regexp.last_match(1)}#{file_url(Regexp.last_match(2), base, version)}#{Regexp.last_match(1)})"
      end
    end

    def find(scope, selector)
      return nil if scope.nil? || selector.blank?

      scope.at_css(selector.to_s.sub(/\A:scope\s*>?\s*/, ''))
    rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError
      nil
    end

    def link_to_path(node, path)
      return unless node

      link = node.name == 'a' ? node : node.ancestors('a').first
      link ||= node.at_css('a')
      if link
        link['href'] = path
      else
        node.wrap(%(<a href="#{path}" style="color:inherit;text-decoration:none"></a>))
      end
    end

    def link_shop(doc, page_map)
      { 'cart_link' => '/cart', 'account_link' => '/account', 'search_link' => '/products', 'logo_link' => '/' }.each do |key, path|
        link_to_path(find(doc, page_map[key]), path)
      end
    end

    # Keeps ONE product card as a template between <!--tellora-card--> markers.
    # Returns { products: number of cards (0 when no grid was found), sale_label: badge text }
    def template_products(doc, page_map)
      grid = find(doc, page_map['product_grid'])
      return { products: 0, sale_label: '' } unless grid

      selector = page_map['product_card'].to_s.sub(/\A:scope\s*>?\s*/, '')
      cards = begin
        selector.present? ? grid.css(selector).to_a : []
      rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError
        []
      end
      cards = cards.select { |card| card.parent == grid }.presence || cards.presence || grid.element_children.to_a
      card = cards.first
      return { products: 0, sale_label: '' } unless card

      name = find(card, page_map['card_name'])
      price = find(card, page_map['card_price'])
      return { products: 0, sale_label: '' } unless name && price

      name.content = '{{name}}'
      price.content = '{{price}}'
      if (compare = find(card, page_map['card_compare_price']))
        compare.content = '{{compare_price}}'
        compare['data-tellora-empty'] = ''
      end
      sale_label = ''
      if (badge = find(card, page_map['card_sale_label']))
        sale_label = badge.text.strip
        badge.content = '{{sale_label}}'
        badge['data-tellora-empty'] = ''
      end
      if (image = find(card, page_map['card_image']) || card.at_css('img'))
        image['src'] = '{{image}}'
        image['alt'] = '{{name}}'
        %w[srcset sizes data-src data-srcset].each { |attr| image.remove_attribute(attr) }
      end
      card.css('a').each { |a| a['href'] = '{{url}}' }
      card['href'] = '{{url}}' if card.name == 'a'
      if (button = find(card, page_map['card_button'])) && button.name != 'a' && button.ancestors('a').empty?
        button.wrap('<a href="{{url}}" style="color:inherit;text-decoration:none"></a>')
      end

      count = cards.size
      cards.each(&:remove)
      grid['data-tellora-products'] = count.to_s
      grid.add_child(Nokogiri::XML::Comment.new(doc, 'tellora-card'))
      grid.add_child(card)
      grid.add_child(Nokogiri::XML::Comment.new(doc, '/tellora-card'))
      { products: count, sale_label: sale_label }
    end
  end
end
