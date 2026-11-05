# frozen_string_literal: true

require 'resolv'

# Checks a StoreDomain's DNS records against public DNS (Google and Cloudflare
# resolvers, so the server's own DNS cache never hides a fresh change).
#
#   DomainVerifier.new(domain).call  # => { ok: true/false, records: {...}, message: "..." }
#
# When everything is correct the domain moves to "issuing" and the certbot agent
# picks it up to get its SSL certificate.
class DomainVerifier
  NAMESERVERS = %w[1.1.1.1 8.8.8.8].freeze
  TIMEOUT = 4 # seconds per lookup

  def self.server_ip
    ENV['TELLORA_SERVER_IP'].presence || begin
      domain = TenantResolver.platform_domains.first
      domain ? new(nil).send(:addresses, domain).first : nil
    end
  end

  def self.store_host(domain)
    store = Spree::Store.find_by(id: domain.store_id)
    host = store&.url.to_s.sub(%r{\Ahttps?://}, '').split('/').first.to_s.split(':').first
    host.presence || "#{domain.tenant_code}.#{TenantResolver.platform_domains.first}"
  end

  def initialize(domain)
    @domain = domain
  end

  # Checks DNS and saves the result on the domain. Never raises.
  def call
    expected_ip = self.class.server_ip
    report = { 'checked_at' => Time.current.iso8601, 'records' => {} }

    txt_found = txt_values(@domain.txt_name)
    report['records']['txt'] = {
      'ok' => txt_found.include?(@domain.txt_value),
      'found' => txt_found.first(3),
      'hint' => (txt_found.empty? ? 'No TXT record found yet' : 'A TXT record exists but its value is different')
    }

    @domain.hostnames.each do |name|
      key = if @domain.apex?
              name == @domain.host ? 'apex' : 'www'
            else
              'host'
            end
      ips = addresses(name)
      ipv6 = addresses(name, Resolv::DNS::Resource::IN::AAAA)
      ok = expected_ip.present? && ips.include?(expected_ip) && (ips - [expected_ip]).empty?
      report['records'][key] = { 'ok' => ok, 'found' => ips.first(4), 'hint' => routing_hint(ips, ipv6, expected_ip) }
      report['records'][key]['ipv6'] = ipv6.first(2) if ipv6.any?
      # Let's Encrypt checks IPv6 first: an AAAA record pointing elsewhere blocks SSL
      report['records'][key]['ok'] = false if ipv6.any?
    end

    report['ok'] = report['records'].values.all? { |r| r['ok'] }
    report['message'] = summary(report)
    save(report)
    report
  rescue StandardError => e
    Rails.logger.error("[DomainVerifier] #{@domain&.host}: #{e.class} - #{e.message}")
    { 'ok' => false, 'records' => {}, 'message' => 'We could not check your DNS right now. We will try again shortly.' }
  end

  private

  def save(report)
    attrs = {
      dns_report: report,
      last_checked_at: Time.current,
      check_count: @domain.check_count.to_i + 1
    }
    if report['ok'] && (@domain.pending? || @domain.failed?)
      attrs[:status] = 'issuing'
      attrs[:verified_at] = @domain.verified_at || Time.current
      attrs[:error] = nil
    end
    @domain.update_columns(attrs.merge(updated_at: Time.current))
  end

  def routing_hint(ips, ipv6, expected_ip)
    return 'Remove the AAAA (IPv6) record for this name' if ipv6.any?
    return 'No record found yet' if ips.empty?
    return nil if ips == [expected_ip]
    return 'Remove the other A records for this name, keep only ours' if ips.include?(expected_ip)

    'Points somewhere else. If you use Cloudflare, turn the proxy off (grey cloud)'
  end

  def summary(report)
    return 'All records are correct. Securing your domain with SSL now.' if report['ok']

    missing = report['records'].count { |_, r| !r['ok'] }
    "#{missing} of #{report['records'].size} records are not correct yet. DNS changes can take up to an hour to appear."
  end

  def txt_values(name)
    resolve(name, Resolv::DNS::Resource::IN::TXT).flat_map { |r| r.strings.join }.uniq
  end

  def addresses(name, type = Resolv::DNS::Resource::IN::A)
    resolve(name, type).map { |r| r.address.to_s }.uniq
  end

  def resolve(name, type)
    Resolv::DNS.open(nameserver: NAMESERVERS) do |dns|
      dns.timeouts = TIMEOUT
      dns.getresources(name, type)
    end
  rescue StandardError
    []
  end
end
