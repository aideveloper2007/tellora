# frozen_string_literal: true

require 'erb'

# Keeps a newly built store private until its owner presses Publish.
#
# Visitors to an unpublished store see an "Opening soon" page.
# The signed-in owner (or an admin) sees the real store, and admin, login,
# builder and asset paths always work so the owner can finish setting up.
#
# Runs right after CustomDomainTenantElevator, so the store's tenant is already active.
class StorePublishGate
  ALWAYS_OPEN = %w[/admin /user /tellora /assets /rails /up /cable /favicon /robots.txt /account /login /logout].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return coming_soon(env['apartment.tenant'], env['REQUEST_METHOD']) if blocked?(env)

    @app.call(env)
  end

  private

  # Decides whether to show "Opening soon". Errors here never take a store down.
  def blocked?(env)
    tenant = env['apartment.tenant']
    return false if tenant.blank? || tenant == TenantResolver::PUBLIC

    path = env['PATH_INFO'].to_s
    return false if ALWAYS_OPEN.any? { |prefix| path.start_with?(prefix) }
    return false unless StoreBuild.private_store?(tenant)

    !owner_signed_in?(env, tenant)
  rescue StandardError => e
    Rails.logger.error("[StorePublishGate] #{e.class} - #{e.message}")
    false
  end

  def owner_signed_in?(env, tenant)
    warden = env['warden']
    return false unless warden

    user = warden.user(Spree.user_class.model_name.singular_route_key.to_sym)
    build = StoreBuild.for_tenant(tenant)
    build.present? && build.owner?(user)
  end

  def coming_soon(tenant, method)
    build = StoreBuild.where(tenant_code: tenant).order(:id).last
    name = ERB::Util.html_escape(build&.store_name.presence || 'This store')
    status = method == 'GET' || method == 'HEAD' ? 200 : 403

    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="robots" content="noindex"><title>#{name} is opening soon</title>
      <style>
        :root { --ink:#18163a; --muted:#5b5e78; --mist:#f1f2f7; --marigold:#f2b100; }
        * { box-sizing: border-box; }
        body { margin:0; min-height:100vh; display:grid; place-items:center; background:var(--mist); color:var(--ink);
               font-family: 'Segoe UI', system-ui, sans-serif; padding: 1.5rem; }
        main { max-width: 32rem; text-align:center; }
        .mark { width:3.25rem; height:3.25rem; border-radius:50%; background:var(--marigold); margin:0 auto 1.5rem; }
        h1 { font-size: clamp(1.8rem, 1.2rem + 3vw, 2.8rem); line-height:1.1; margin:0; letter-spacing:-0.02em; }
        p { color:var(--muted); font-size:1.1rem; line-height:1.55; margin:1rem 0 0; }
        a { color:var(--ink); }
      </style></head>
      <body><main>
        <div class="mark" aria-hidden="true"></div>
        <h1>#{name} is opening soon</h1>
        <p>The store is being set up. Please check back shortly.</p>
        <p><a href="/user/sign_in">Store owner? Sign in</a></p>
      </main></body></html>
    HTML

    [status, { 'content-type' => 'text/html; charset=utf-8', 'cache-control' => 'no-store' }, [html]]
  end
end
