# frozen_string_literal: true

# Saves an AI-generated theme into a store and makes it the active design.
# Call inside the store's tenant: Apartment::Tenant.switch(code) { ThemeApplier.new(...).apply!(data) }
#
# Besides the theme itself, every applied theme gets a home page plan and a
# designer-made style family (see PagePlan and StyleFamily). When a design is
# refined in the builder, the plan and photos of the previous design are kept.
class ThemeApplier
  def initialize(store:, store_name:, prompt:)
    @store = store
    @store_name = store_name
    @prompt = prompt
  end

  def apply!(theme_data)
    data = normalize(theme_data)
    ensure_theme_images_table

    previous = @store.themes.find_by(default: true)
    previous = nil unless previous.is_a?(Spree::Themes::GenAi)

    theme = Spree::Themes::GenAi.create_from_api_response(data, @store, nil)
    if data['images'].present? && theme.respond_to?(:theme_images)
      ThemeImageManager.new(theme).download_and_attach_images(data['images'])
    end

    # Words, photos and style family for the home page (never raises)
    PagePlan.apply!(theme: theme, store: @store, description: @prompt, previous_theme: previous)

    theme.update!(ready: true)
    @store.themes.where(default: true).where.not(id: theme.id).update_all(default: false)
    theme.update!(default: true)
    theme
  end

  private

  def normalize(theme_data)
    data = (theme_data || {}).deep_dup
    raise 'The generated theme has no data' if data.blank?

    data['metadata'] = (data['metadata'] || {}).merge(
      'store_name' => data.dig('metadata', 'store_name').presence || @store_name,
      'store_type' => data.dig('metadata', 'store_type').presence || @prompt.to_s.truncate(120),
      'original_prompt' => @prompt
    )
    data
  end

  # Same lazy table creation the GenAI theme controller uses
  def ensure_theme_images_table
    connection = ActiveRecord::Base.connection
    return if connection.table_exists?('theme_images')

    ActiveRecord::Migration.suppress_messages do
      connection.create_table :theme_images do |t|
        t.references :theme, foreign_key: { to_table: :spree_themes }, null: false
        t.string :section, null: false
        t.string :source_url
        t.string :source_attribution
        t.text :metadata
        t.timestamps
      end
      connection.add_index :theme_images, [:theme_id, :section], unique: true
    end
  end
end