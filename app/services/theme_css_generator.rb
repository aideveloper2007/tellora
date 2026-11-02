# frozen_string_literal: true

class ThemeCssGenerator
  attr_reader :theme
  
  def initialize(theme)
    @theme = theme
    @config = theme.preferences || {}
  end
  
  # Generate full CSS for theme
  def generate_full_css
    parts = []
    
    # 1. CSS Variables (colors, fonts, spacing)
    parts << generate_css_variables
    
    # 2. Typography imports (Google Fonts, etc.)
    parts << generate_font_imports
    
    # 3. Global styles
    parts << generate_global_styles
    
    # 4. Component styles (buttons, cards, etc.)
    parts << generate_component_styles
    
    # 5. Layout styles
    parts << generate_layout_styles
    
    parts.compact.join("\n\n")
  end
  
  # Generate only CSS variables (for quick updates)
  def generate_css_variables
    colors = @config['color_palette'] || {}
    typography = @config['typography'] || {}
    layout = @config['layout_config'] || {}
    
    <<~CSS
      /* GenAI Theme CSS Variables - Theme ID: #{theme.id} */
      :root {
        /* Colors */
        --genai-primary: #{colors['primary'] || '#333333'};
        --genai-secondary: #{colors['secondary'] || '#666666'};
        --genai-accent: #{colors['accent'] || '#007bff'};
        --genai-background: #{colors['background'] || '#ffffff'};
        --genai-text: #{colors['text'] || '#333333'};
        --genai-text-secondary: #{colors['text_secondary'] || '#666666'};
        --genai-border: #{colors['border'] || '#e0e0e0'};
        --genai-hover: #{colors['hover'] || '#f5f5f5'};
        
        /* Typography */
        --genai-font-heading: #{font_stack(typography['heading_font'])};
        --genai-font-body: #{font_stack(typography['body_font'])};
        --genai-font-size-base: #{typography['font_size_base'] || '16px'};
        --genai-line-height: #{typography['line_height'] || '1.6'};
        
        /* Spacing */
        --genai-spacing-section: #{layout['section_padding'] || '80px'};
        --genai-spacing-element: #{layout['element_gap'] || '24px'};
        --genai-border-radius: #{layout['border_radius'] || '8px'};
        
        /* Layout */
        --genai-container-width: #{layout['container_width'] || '1200px'};
        --genai-grid-columns: #{layout['grid_columns'] || '3'};
      }
    CSS
  end
  
  # Generate @import statements for fonts
  def generate_font_imports
    typography = @config['typography'] || {}
    imports = []
    
    if typography['heading_font'].present?
      imports << google_font_import(typography['heading_font'])
    end
    
    if typography['body_font'].present? && typography['body_font'] != typography['heading_font']
      imports << google_font_import(typography['body_font'])
    end
    
    imports.compact.join("\n")
  end
  
  # Generate global styles
  def generate_global_styles
    <<~CSS
      /* GenAI Global Styles */
      body.genai-theme {
        font-family: var(--genai-font-body);
        font-size: var(--genai-font-size-base);
        line-height: var(--genai-line-height);
        color: var(--genai-text);
        background-color: var(--genai-background);
      }
      
      .genai-theme h1,
      .genai-theme h2,
      .genai-theme h3,
      .genai-theme h4,
      .genai-theme h5,
      .genai-theme h6 {
        font-family: var(--genai-font-heading);
        color: var(--genai-primary);
      }
      
      .genai-theme a {
        color: var(--genai-accent);
        text-decoration: none;
      }
      
      .genai-theme a:hover {
        color: var(--genai-primary);
      }
    CSS
  end
  
  # Generate component styles (buttons, cards, etc.)
  def generate_component_styles
    components = @config['component_styles'] || {}
    button_config = components['button'] || {}
    card_config = components['card'] || {}
    
    <<~CSS
      /* GenAI Component Styles */
      
      /* Buttons */
      .genai-btn {
        font-family: var(--genai-font-body);
        font-size: 16px;
        padding: 12px 24px;
        border-radius: var(--genai-border-radius);
        border: none;
        cursor: pointer;
        transition: all 0.3s ease;
        display: inline-block;
      }
      
      .genai-btn-primary {
        background-color: var(--genai-accent);
        color: white;
      }
      
      .genai-btn-primary:hover {
        background-color: var(--genai-primary);
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
      }
      
      .genai-btn-secondary {
        background-color: var(--genai-secondary);
        color: white;
      }
      
      .genai-btn-secondary:hover {
        background-color: var(--genai-primary);
      }
      
      /* Cards */
      .genai-card {
        background: var(--genai-background);
        border: 1px solid var(--genai-border);
        border-radius: var(--genai-border-radius);
        padding: var(--genai-spacing-element);
        transition: transform 0.3s ease, box-shadow 0.3s ease;
      }
      
      .genai-card:hover {
        transform: translateY(-4px);
        box-shadow: 0 8px 24px rgba(0,0,0,0.12);
      }
      
      /* Product Cards */
      .genai-product-card {
        background: var(--genai-background);
        border: 1px solid var(--genai-border);
        border-radius: var(--genai-border-radius);
        overflow: hidden;
        transition: all 0.3s ease;
      }
      
      .genai-product-card:hover {
        box-shadow: #{card_config['hover_shadow'] || '0 8px 24px rgba(0,0,0,0.12)'};
        transform: translateY(-4px);
      }
      
      .genai-product-card img {
        width: 100%;
        height: auto;
        object-fit: cover;
      }
      
      .genai-product-card .product-info {
        padding: 16px;
      }
      
      .genai-product-card .product-name {
        font-family: var(--genai-font-heading);
        font-size: 18px;
        color: var(--genai-primary);
        margin-bottom: 8px;
      }
      
      .genai-product-card .product-price {
        font-size: 20px;
        font-weight: bold;
        color: var(--genai-accent);
      }
    CSS
  end
  
  # Generate layout styles
  def generate_layout_styles
    layout = @config['layout_config'] || {}
    
    <<~CSS
      /* GenAI Layout Styles */
      
      .genai-container {
        max-width: var(--genai-container-width);
        margin: 0 auto;
        padding: 0 24px;
      }
      
      .genai-section {
        padding: var(--genai-spacing-section) 0;
      }
      
      .genai-grid {
        display: grid;
        grid-template-columns: repeat(var(--genai-grid-columns), 1fr);
        gap: var(--genai-spacing-element);
      }
      
      @media (max-width: 768px) {
        :root {
          --genai-grid-columns: 2;
          --genai-spacing-section: 40px;
        }
        
        .genai-grid {
          grid-template-columns: repeat(2, 1fr);
        }
      }
      
      @media (max-width: 480px) {
        :root {
          --genai-grid-columns: 1;
        }
        
        .genai-grid {
          grid-template-columns: 1fr;
        }
      }
      
      /* Hero Section */
      .genai-hero {
        position: relative;
        min-height: #{layout['hero_height'] || '600px'};
        display: flex;
        align-items: center;
        justify-content: center;
        background-size: cover;
        background-position: center;
      }
      
      .genai-hero-overlay {
        position: absolute;
        inset: 0;
        background: rgba(0,0,0,0.3);
      }
      
      .genai-hero-content {
        position: relative;
        z-index: 1;
        text-align: center;
        color: white;
        max-width: 800px;
        padding: 40px;
      }
      
      .genai-hero-heading {
        font-size: #{layout['hero_heading_size'] || '48px'};
        font-weight: bold;
        margin-bottom: 24px;
        text-shadow: 0 2px 4px rgba(0,0,0,0.3);
      }
      
      .genai-hero-subheading {
        font-size: #{layout['hero_subheading_size'] || '24px'};
        margin-bottom: 32px;
        text-shadow: 0 2px 4px rgba(0,0,0,0.3);
      }
    CSS
  end
  
  private
  
  def font_stack(font_name)
    return "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif" if font_name.blank?
    
    case font_name.downcase
    when /playfair/
      "'Playfair Display', Georgia, serif"
    when /montserrat/
      "'Montserrat', -apple-system, BlinkMacSystemFont, sans-serif"
    when /inter/
      "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    when /roboto/
      "'Roboto', -apple-system, BlinkMacSystemFont, sans-serif"
    when /lato/
      "'Lato', -apple-system, BlinkMacSystemFont, sans-serif"
    when /open sans/
      "'Open Sans', -apple-system, BlinkMacSystemFont, sans-serif"
    else
      "'#{font_name}', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    end
  end
  
  def google_font_import(font_name)
    return nil if font_name.blank?
    
    # Common Google Fonts
    font_slug = font_name.gsub(' ', '+')
    "@import url('https://fonts.googleapis.com/css2?family=#{font_slug}:wght@400;500;600;700&display=swap');"
  end
end
