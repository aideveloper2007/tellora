# frozen_string_literal: true

require 'resolv'

# "Move my store": before Tellora reads someone's existing store, they prove
# they control its domain with a DNS TXT record. Without this, anyone could
# copy a competitor's brand into a new store.
#
#   url, host = ImportOwnership.normalize('www.mybrand.com')  # raises ImportOwnership::Invalid
#   ImportOwnership.record_name(host)    # => "_tellora.mybrand.com"
#   ImportOwnership.record_value(token)  # => "tellora-verify=..."
#   ImportOwnership.verified?(host, token)
class ImportOwnership
  NAMESERVERS = %w[1.1.1.1 8.8.8.8].freeze
  TIMEOUT = 4 # seconds

  # Addresses on other platforms' own domains: the owner cannot add DNS records there
  PLATFORM_SUFFIXES = %w[
    myshopify.com shopify.com wixsite.com wix.com squarespace.com square.site
    shoparena.pl shoper.pl mybigcommerce.com wordpress.com blogspot.com
    weebly.com webflow.io netlify.app vercel.app github.io
  ].freeze

  class Invalid < StandardError; end

  class << self
    # Returns [home page URL, domain without www]
    def normalize(input)
      text = input.to_s.strip.downcase
      raise Invalid, 'Enter the web address of your current store, like mybrand.com' if text.blank?

      text = "https://#{text}" unless text.match?(%r{\Ahttps?://})
      uri = URI.parse(text)
      host = uri.host.to_s.sub(/\.\z/, '')

      raise Invalid, 'That does not look like a web address' unless host.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/)
      raise Invalid, 'Enter a domain name, not an IP address' if host.match?(/\A[\d.]+\z/)

      domain = host.sub(/\Awww\./, '')
      if TenantResolver.platform_domains.any? { |d| domain == d || domain.end_with?(".#{d}") }
        raise Invalid, 'That address is already on Tellora'
      end
      if PLATFORM_SUFFIXES.any? { |s| domain == s || domain.end_with?(".#{s}") }
        raise Invalid, "Use your own domain (like mybrand.com), not the #{domain.split('.').last(2).join('.')} address. " \
                       'We check you own it with a DNS record, which only works on your own domain.'
      end

      ["https://#{host}/", domain]
    rescue URI::InvalidURIError
      raise Invalid, 'That does not look like a web address'
    end

    def record_name(domain)
      "_tellora.#{domain}"
    end

    def record_value(token)
      "tellora-verify=#{token}"
    end

    def verified?(domain, token)
      return false if domain.blank? || token.blank?

      txt_values(record_name(domain)).include?(record_value(token))
    end

    private

    def txt_values(name)
      Resolv::DNS.open(nameserver: NAMESERVERS) do |dns|
        dns.timeouts = TIMEOUT
        dns.getresources(name, Resolv::DNS::Resource::IN::TXT).map { |r| r.strings.join }
      end
    rescue StandardError
      []
    end
  end
end
