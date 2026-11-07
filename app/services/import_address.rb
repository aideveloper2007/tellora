# frozen_string_literal: true

# "Move my store": cleans up the address of the store the owner is moving from.
#
#   url, domain = ImportAddress.normalize('www.MyBrand.com/collections/all')
#   # => ["https://www.mybrand.com/", "mybrand.com"]
#
# Any public store address works (mybrand.com, mybrand.myshopify.com, ...).
# The owner's own domain is connected later, from the Domain screen, once they
# are happy with the new store (that step checks DNS).
class ImportAddress
  class Invalid < StandardError; end

  HOST_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/

  # Returns [home page URL, domain without www]
  def self.normalize(input)
    text = input.to_s.strip.downcase
    raise Invalid, 'Enter the web address of your current store, like mybrand.com' if text.blank?

    text = "https://#{text}" unless text.match?(%r{\Ahttps?://})
    host = URI.parse(text).host.to_s.sub(/\.\z/, '')

    raise Invalid, 'That does not look like a web address' unless host.match?(HOST_FORMAT)
    raise Invalid, 'Enter a domain name, not an IP address' if host.match?(/\A[\d.]+\z/)

    domain = host.sub(/\Awww\./, '')
    if TenantResolver.platform_domains.any? { |d| domain == d || domain.end_with?(".#{d}") }
      raise Invalid, 'That address is already on Tellora'
    end

    ["https://#{host}/", domain]
  rescue URI::InvalidURIError
    raise Invalid, 'That does not look like a web address'
  end
end
