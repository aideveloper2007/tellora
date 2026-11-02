# frozen_string_literal: true

# Tellora maintenance tasks.
#
#   bin/rails "tellora:upgrade_store[cafedeespecial]"   give an existing store the designer home page
#   bin/rails "tellora:remove_family[cafedeespecial]"   go back to the previous home page
namespace :tellora do
  desc 'Give an existing store its style family and an AI page plan (words + photos)'
  task :upgrade_store, [:code] => :environment do |_task, args|
    store, tenant = tellora_find_store(args[:code])

    host = store.url.to_s.sub(%r{\Ahttps?://}, '').split('/').first.to_s.split(':').first
    if host.present? && host != store.url
      store.update_columns(url: host)
      puts "Store address saved as #{host}"
    end

    Apartment::Tenant.switch(tenant) do
      theme = store.themes.find_by(default: true)
      abort 'This store has no AI theme yet. Build or apply a theme first.' unless theme.is_a?(Spree::Themes::GenAi)

      build = StoreBuild.find_by(store_id: store.id)
      prefs = theme.preferences || {}
      description = build&.prompt.presence || prefs['original_prompt'].presence || prefs[:original_prompt].presence || store.name

      puts 'Writing the home page words and finding photos (about 30 to 60 seconds)...'
      PagePlan.apply!(theme: theme, store: store, description: description)

      family = PagePlan.family_of(theme.reload)
      photos = PagePlan::IMAGE_SLOTS.count { |slot| PagePlan.image(theme, slot)&.image&.attached? }
      puts "Done: #{store.name} now uses the #{StyleFamily::FAMILIES.dig(family, :name) || family} style, with #{photos} of 3 section photos."
    end

    TenantResolver.clear(host) if host.present?
  end

  desc 'Remove the style family from a store (its previous home page comes back)'
  task :remove_family, [:code] => :environment do |_task, args|
    store, tenant = tellora_find_store(args[:code])

    StyleFamily.remove!(store)
    Apartment::Tenant.switch(tenant) do
      theme = store.themes.find_by(default: true)
      if theme
        prefs = (theme.preferences || {}).to_h.reject { |k, _| k.to_s == 'style_family' }
        theme.update_column(:preferences, prefs)
      end
    end
    puts "Style family removed from #{store.name}. The page plan is kept, so upgrade_store can bring it back."
  end

  def tellora_find_store(code)
    code = code.to_s.strip
    abort 'Give the store code, for example: bin/rails "tellora:upgrade_store[cafedeespecial]"' if code.blank?

    store = Spree::Store.find_by(code: code)
    abort "No store found with code #{code}" unless store

    build = StoreBuild.find_by(store_id: store.id)
    [store, build&.tenant_code.presence || store.code]
  end
end
