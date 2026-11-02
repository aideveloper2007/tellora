# frozen_string_literal: true

class ThemeImageManager
  attr_reader :theme
  
  def initialize(theme)
    @theme = theme
  end
  
  # Download Pixabay images and attach to theme
  # Expected format: { hero: {...}, products: [{...}, ...] }
  def download_and_attach_images(pixabay_images)
    Rails.logger.info "=== Downloading images for theme #{theme.id} ==="
    
    downloaded_images = []
    
    # Download hero image
    if pixabay_images['hero'].present?
      hero_image = download_image(
        pixabay_images['hero']['url'],
        'hero',
        pixabay_images['hero']
      )
      downloaded_images << hero_image if hero_image
    end
    
    # Download product images
    if pixabay_images['products'].present?
      pixabay_images['products'].each_with_index do |product_img, idx|
        next unless product_img['preview_url'].present?
        
        product_image = download_image(
          product_img['preview_url'],
          "product_#{idx + 1}",
          product_img
        )
        downloaded_images << product_image if product_image
      end
    end
    
    Rails.logger.info "Downloaded #{downloaded_images.length} images successfully"
    downloaded_images
  rescue StandardError => e
    Rails.logger.error "Failed to download images: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    []
  end
  
  # Replace a specific section's image (for future refinement feature)
  def replace_image(section_type, new_image_url, metadata = {})
    Rails.logger.info "Replacing #{section_type} image with #{new_image_url}"
    
    # Delete old image for this section
    theme.theme_images.where(section: section_type).destroy_all
    
    # Download new image
    download_image(new_image_url, section_type, metadata)
  end
  
  private
  
  def download_image(url, section_identifier, metadata = {})
    require 'open-uri'
    
    Rails.logger.info "Downloading image: #{url} for section: #{section_identifier}"
    
    # Download file
    file = URI.open(url, read_timeout: 30)
    
    # Create blob
    filename = "#{theme.id}_#{section_identifier}_#{Time.current.to_i}.jpg"
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file,
      filename: filename,
      content_type: 'image/jpeg'
    )
    
    # Create ThemeImage record
    theme_image = theme.theme_images.create!(
      section: section_identifier,
      source_url: url,
      source_attribution: metadata['photographer'] || metadata['user'],
      metadata: metadata.to_json
    )
    
    # Attach blob to image
    theme_image.image.attach(blob)
    
    Rails.logger.info "Image downloaded successfully: #{theme_image.id}"
    theme_image
  rescue OpenURI::HTTPError => e
    Rails.logger.error "HTTP error downloading image from #{url}: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "Error downloading image from #{url}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    nil
  end
end
