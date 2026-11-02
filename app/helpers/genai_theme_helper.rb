# frozen_string_literal: true

module GenaiThemeHelper
  # Check if current store has an active GenAI theme
  def using_genai_theme?
    active_theme = current_store.themes.find_by(default: true)
    active_theme&.type == 'Spree::Themes::GenAi'
  end
  
  # Get the current GenAI theme
  def current_genai_theme
    return nil unless using_genai_theme?
    @current_genai_theme ||= current_store.themes.find_by(default: true)
  end
  
  # Render GenAI theme CSS
  def genai_theme_css
    return '' unless using_genai_theme?
    
    # Use string key 'custom_css' instead of symbol :custom_css
    # PostgreSQL JSON columns store keys as strings, not symbols
    custom_css = current_genai_theme.preferences['custom_css']
    
    # Prefer Claude-generated CSS (includes nav/footer styling)
    if custom_css.present?
      raw(custom_css)
    else
      # Fallback to Ruby generator (for older themes without custom_css)
      css_generator = ThemeCssGenerator.new(current_genai_theme)
      raw(css_generator.generate_full_css)
    end
  end
  
  # Get theme color
  def genai_color(color_key)
    return nil unless using_genai_theme?
    current_genai_theme.colors[color_key.to_s]
  end
  
  # Get theme font
  def genai_font(font_key)
    return nil unless using_genai_theme?
    current_genai_theme.fonts[font_key.to_s]
  end
  
  # Get hero image
  def genai_hero_image
    return nil unless using_genai_theme?
    current_genai_theme.hero_image
  end
  
  # Get product images
  def genai_product_images
    return [] unless using_genai_theme?
    current_genai_theme.product_images.to_a
  end
  
  # Get layout config value
  def genai_layout(key)
    return nil unless using_genai_theme?
    current_genai_theme.layout[key.to_s]
  end
  
  # Apply body class for GenAI theme
  def genai_body_class
    using_genai_theme? ? 'genai-theme' : ''
  end
  
  # Render hero section
  def render_genai_hero
    return '' unless using_genai_theme?
    render partial: 'shared/genai_hero'
  end
  
  # Render featured products with GenAI styling
  def render_genai_featured_products(products)
    return '' unless using_genai_theme?
    render partial: 'shared/genai_featured_products', locals: { products: products }
  end
  
  # Check if promotional banner is enabled
  def genai_promo_banner_enabled?
    return false unless using_genai_theme?
    
    page_config = current_genai_theme.preferences[:page_configs] || {}
    homepage_config = page_config['homepage'] || {}
    promo_config = homepage_config['promo_banner'] || {}
    
    promo_config['enabled'] == true
  end
  
  # Get promotional banner config
  def genai_promo_banner
    return nil unless genai_promo_banner_enabled?
    
    page_config = current_genai_theme.preferences[:page_configs] || {}
    homepage_config = page_config['homepage'] || {}
    homepage_config['promo_banner']
  end
end
