class CreateThemeImages < ActiveRecord::Migration[7.0]
  def change
    create_table :theme_images do |t|
      t.references :theme, null: false, foreign_key: { to_table: :spree_themes }
      t.string :section, null: false  # hero, product_1, product_2, etc.
      t.string :source_url, null: false
      t.string :source_attribution  # Photographer credit from Pixabay
      t.text :metadata  # Store additional info like tags, dimensions
      t.timestamps
    end
    
    add_index :theme_images, [:theme_id, :section], unique: true
  end
end
