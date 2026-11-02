module ApplicationHelper
  # Generate inline styles for theme preview
  def generate_preview_styles(theme)
    return "" unless theme.is_a?(Hash)
    
    styles = []
    
    if theme['color_palette']
      styles << "background-color: #{theme['color_palette']['background']}"
      styles << "color: #{theme['color_palette']['text']}"
    end
    
    if theme['layout']
      styles << "border-radius: #{theme['layout']['border_radius']}" if theme['layout']['border_radius']
    end
    
    styles.join('; ')
  end
end