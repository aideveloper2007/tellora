# frozen_string_literal: true

# One-time, short-lived sign-in link from the platform into a newly built store.
# The platform and the store live on different hosts, so the session cannot be shared directly.
module StoreHandoff
  PURPOSE = :store_handoff
  EXPIRES_IN = 10.minutes

  module_function

  def issue(build)
    verifier.generate({ 'build_id' => build.id, 'tenant' => build.tenant_code }, expires_in: EXPIRES_IN, purpose: PURPOSE)
  end

  # Returns the StoreBuild if the token is valid, unused and meant for this tenant; otherwise nil
  def redeem(token, tenant)
    payload = verifier.verified(token.to_s, purpose: PURPOSE)
    return nil unless payload.is_a?(Hash) && payload['tenant'] == tenant

    build = StoreBuild.find_by(id: payload['build_id'], tenant_code: tenant, status: 'done')
    return nil if build.nil? || build.handoff_used_at.present?

    # Mark used atomically, so the same link can never sign in twice
    updated = StoreBuild.where(id: build.id, handoff_used_at: nil).update_all(handoff_used_at: Time.current)
    updated == 1 ? build : nil
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
