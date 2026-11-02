# frozen_string_literal: true

# Runs a store build in the background (Sidekiq).
# No automatic retries: a failed build stays visible and the owner can press "Try again",
# which continues from the step that failed.
class StoreBuildJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(build_id)
    build = StoreBuild.find_by(id: build_id)
    return unless build
    return if build.status == 'done'

    StoreProvisioner.new(build).call
  ensure
    Apartment::Tenant.reset
  end
end
