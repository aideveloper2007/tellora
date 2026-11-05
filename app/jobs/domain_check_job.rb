# frozen_string_literal: true

# Checks a custom domain's DNS in the background.
# While the domain is still waiting for DNS it checks again every 10 minutes, for up to 3 days.
# The owner can also press "Check now" on the Domain screen at any time.
class DomainCheckJob
  include Sidekiq::Job
  sidekiq_options retry: false

  RECHECK_EVERY = 10 * 60 # seconds
  GIVE_UP_AFTER = 3 * 24 * 60 * 60 # seconds since the domain was added

  def perform(domain_id)
    domain = StoreDomain.find_by(id: domain_id)
    return unless domain&.pending? || domain&.failed?

    report = DomainVerifier.new(domain).call
    return if report['ok']
    return if domain.created_at < GIVE_UP_AFTER.seconds.ago

    self.class.perform_in(RECHECK_EVERY, domain.id)
  end
end
