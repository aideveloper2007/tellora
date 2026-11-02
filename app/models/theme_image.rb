# frozen_string_literal: true

class ThemeImage < ApplicationRecord
  belongs_to :theme, class_name: 'Spree::Theme'
  has_one_attached :image
  
  validates :section, presence: true
  validates :source_url, presence: true
  validates :section, uniqueness: { scope: :theme_id }
  
  # Scopes
  scope :for_section, ->(section_name) { where(section: section_name) }
  scope :hero_images, -> { where(section: 'hero') }
  scope :product_images, -> { where("section LIKE ?", "product_%") }
  
  # Instance methods
  def hero?
    section == 'hero'
  end
  
  def product?
    section.start_with?('product_')
  end
  
  def product_index
    return nil unless product?
    section.gsub('product_', '').to_i
  end
  
  def image_url
    if image.attached?
      Rails.application.routes.url_helpers.rails_blob_url(image, only_path: true)
    else
      source_url  # Fallback to Pixabay URL if not downloaded yet
    end
  end
  
  def metadata_hash
    metadata.present? ? JSON.parse(metadata) : {}
  rescue JSON::ParserError
    {}
  end
  
  def photographer
    source_attribution || metadata_hash['photographer']
  end
  
  def pixabay_id
    metadata_hash['pixabay_id']
  end
  
  def tags
    metadata_hash['tags'] || []
  end
end
