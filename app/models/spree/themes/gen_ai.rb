# frozen_string_literal: true

module Spree
  module Themes
    class GenAi < Spree::Theme
      # Store complex data in preferences (JSON storage)
      store_accessor :preferences,
                     :genai_generated,
                     :genai_version,
                     :store_type,
                     :original_prompt,
                     :color_palette,
                     :typography,
                     :layout_config,
                     :component_styles,
                     :custom_css,  # Complete CSS from Claude (includes nav/footer)
                     :page_configs,
                     :modification_history,  # For future refinement feature
                     :scope  # For future multi-page feature
      
      validates :genai_version, presence: true, if: :genai_generated?
      validate :validate_theme_structure
      
      # Associations
      has_many :theme_images, 
               foreign_key: :theme_id, 
               dependent: :destroy, 
               class_name: 'ThemeImage'
      
      # Scopes
      scope :generated, -> { where("preferences @> ?", { genai_generated: true }.to_json) }
      scope :for_store_type, ->(type) { where("preferences @> ?", { store_type: type }.to_json) }
      
      # Class methods
      def self.create_from_api_response(api_data, store, conversation_id = nil)
        theme = new(
          name: "GenAI - #{api_data['metadata']['store_name']}",
          store_id: store.id,
          ready: false,
          default: false
        )
        
        theme.preferences = {
          genai_generated: true,
          genai_version: '1.0',
          store_type: api_data['metadata']['store_type'],
          original_prompt: api_data['metadata']['original_prompt'],
          conversation_id: conversation_id,
          generated_at: Time.current.iso8601,
          
          # Theme data from FastAPI
          color_palette: api_data['colors'] || {},
          typography: api_data['typography'] || {},
          layout_config: api_data['layout'] || {},
          component_styles: api_data['components'] || {},
          custom_css: api_data['css'] || '',  # Complete CSS from Claude (includes nav/footer styling)
          
          # Future features (initialize empty)
          modification_history: [],
          page_configs: { homepage: api_data['layout'] || {} },
          scope: 'homepage_only'  # MVP: homepage only
        }
        
        theme.save!
        theme
      end
      
      # Instance methods
      def genai_generated?
        preferences[:genai_generated] == true
      end
      
      def store_type
        preferences[:store_type]
      end
      
      def colors
        preferences[:color_palette] || {}
      end
      
      def fonts
        preferences[:typography] || {}
      end
      
      def layout
        preferences[:layout_config] || {}
      end
      
      # Spree theme compatibility methods
      def preferred_font_family
        fonts['body_font'] || 'system-ui, sans-serif'
      end
      
      def preferred_heading_font_family
        fonts['heading_font'] || preferred_font_family
      end
      
      def preferred_header_font_family
        fonts['heading_font'] || preferred_font_family
      end
      
      def preferred_font_size
        '16px'
      end
      
      def preferred_header_font_size
        '24px'
      end
      
      def preferred_font_size_scale
        100
      end
      
      def preferred_custom_font_code
        nil
      end
      
      # Future: Refinement support (architecture ready, not implemented yet)
      def supports_refinement?
        genai_generated? && preferences[:modification_history].is_a?(Array)
      end
      
      def apply_refinement(refinement_data, user_message)
        return false unless supports_refinement?
        
        # Future implementation will go here
        # For now, just track the intent
        preferences[:modification_history] ||= []
        preferences[:modification_history] << {
          timestamp: Time.current.iso8601,
          user_request: user_message,
          changes: refinement_data,
          version: preferences[:modification_history].length + 1
        }
        
        # Merge changes into existing preferences
        merge_refinement_changes(refinement_data)
        save!
      end
      
      def rollback_to_version(version_index)
        return false unless supports_refinement?
        return false if version_index >= preferences[:modification_history].length
        
        # Future implementation
        # For now, just validate the capability
        true
      end
      
      # Future: Multi-page support (architecture ready)
      def applies_to_page?(page_type)
        # MVP: Only homepage
        scope_value = preferences[:scope] || 'homepage_only'
        
        case scope_value
        when 'homepage_only'
          page_type == 'Spree::Pages::Homepage'
        when 'storefront_wide'
          # Future: All storefront pages
          page_type.in?(['Spree::Pages::Homepage', 'Spree::Pages::Product', 
                         'Spree::Pages::Category', 'Spree::Pages::Cart'])
        when 'full_site'
          # Future: Everything
          true
        else
          false
        end
      end
      
      # Export theme configuration as JSON
      def export_configuration
        preferences.slice(
          :color_palette, 
          :typography, 
          :layout_config, 
          :component_styles,
          :page_configs
        )
      end
      
      # Get image for a specific section
      def image_for_section(section_name)
        theme_images.find_by(section: section_name)
      end
      
      def hero_image
        image_for_section('hero')
      end
      
      def product_images
        theme_images.where("section LIKE ?", "product_%").order(:section)
      end
      
      private
      
      def validate_theme_structure
        if genai_generated?
          errors.add(:preferences, "must include color_palette") unless preferences[:color_palette].present?
          errors.add(:preferences, "must include typography") unless preferences[:typography].present?
          errors.add(:preferences, "must include layout_config") unless preferences[:layout_config].present?
        end
      end
      
      def merge_refinement_changes(refinement_data)
        # Deep merge refinement into preferences
        case refinement_data[:change_type]
        when 'color'
          preferences[:color_palette].merge!(refinement_data[:modifications] || {})
        when 'typography'
          preferences[:typography].merge!(refinement_data[:modifications] || {})
        when 'layout'
          preferences[:layout_config].merge!(refinement_data[:modifications] || {})
        when 'promo_banner'
          preferences[:page_configs] ||= {}
          preferences[:page_configs][:homepage] ||= {}
          preferences[:page_configs][:homepage][:promo_banner] = refinement_data[:modifications]
        end
      end
    end
  end
end
