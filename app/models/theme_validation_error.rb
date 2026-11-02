# frozen_string_literal: true

# ThemeValidationError captures validation failures to enable learning
# and provide actionable feedback to Claude for retry attempts.
#
# Purpose in Enterprise Architecture:
# - Track why themes fail validation
# - Build feedback for Claude's retry attempts
# - Identify patterns in validation failures
# - Learn which error types are most common
# - Measure auto-fix success rate
#
# Error Types:
#   - 'schema': JSON structure invalid
#   - 'color_contrast': WCAG accessibility violation
#   - 'font': Font not in approved list
#   - 'css': Invalid CSS values/units
#   - 'layout': Responsive design issues
#   - 'security': XSS/injection risks detected
#   - 'image': Invalid image URLs/configuration
#
class ThemeValidationError < ApplicationRecord
  # Associations
  belongs_to :theme_generation
  
  # Validations
  validates :tenant, presence: true
  validates :error_type, presence: true, inclusion: {
    in: %w[schema color_contrast font css layout security image],
    message: "%{value} is not a valid error type"
  }
  validates :error_message, presence: true
  
  # Scopes for analytics
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }
  scope :by_type, ->(type) { where(error_type: type) }
  scope :auto_fixed, -> { where(auto_fixed: true) }
  scope :not_fixed, -> { where(auto_fixed: false) }
  scope :recent, ->(days = 7) { where('created_at >= ?', days.days.ago) }
  
  # Class methods for learning and analytics
  class << self
    # Get most common validation errors for a tenant
    # Helps identify systemic issues in prompting or validation
    #
    # @param tenant [String] Tenant identifier
    # @param limit [Integer] Number of top errors to return
    # @return [Hash] Error type => count
    def top_errors(tenant, limit: 5)
      for_tenant(tenant)
        .recent(30)
        .group(:error_type)
        .count
        .sort_by { |_, count| -count }
        .first(limit)
        .to_h
    end
    
    # Get auto-fix success rate by error type
    # Measures effectiveness of self-healing
    #
    # @param tenant [String] Tenant identifier
    # @return [Hash] Error type => fix rate percentage
    def auto_fix_rates(tenant)
      for_tenant(tenant)
        .recent(30)
        .group(:error_type)
        .select('error_type, 
                 COUNT(*) as total,
                 SUM(CASE WHEN auto_fixed THEN 1 ELSE 0 END) as fixed')
        .map do |result|
          rate = result.total > 0 ? (result.fixed.to_f / result.total * 100).round(2) : 0.0
          [result.error_type, rate]
        end
        .to_h
    end
    
    # Build actionable feedback for Claude retry attempt
    # Converts technical errors into natural language guidance
    #
    # @param generation_id [Integer] ThemeGeneration ID
    # @return [String] Human-readable feedback for Claude
    def build_feedback_for_retry(generation_id)
      errors = where(theme_generation_id: generation_id)
      return "No specific errors found." if errors.empty?
      
      feedback = ["The previous theme had the following issues:\n"]
      
      errors.group_by(&:error_type).each do |error_type, group_errors|
        feedback << "\n#{error_type.titleize} Issues:"
        group_errors.each do |error|
          feedback << "  - #{error.error_message}"
          
          # Add actionable guidance
          case error_type
          when 'color_contrast'
            feedback << "    → Increase contrast ratio or use darker/lighter shades"
          when 'font'
            feedback << "    → Use only approved Google Fonts from the list"
          when 'css'
            feedback << "    → Use valid CSS units (px, %, rem, em) and syntax"
          when 'layout'
            feedback << "    → Ensure responsive design works on mobile, tablet, desktop"
          when 'security'
            feedback << "    → Remove any inline scripts or potentially unsafe content"
          end
        end
      end
      
      feedback << "\nPlease fix these issues in the next attempt."
      feedback.join("\n")
    end
    
    # Track error trends over time
    # Helps identify if validation is improving or regressing
    #
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to analyze
    # @return [Hash] Date => error count
    def error_trend(tenant, days: 30)
      for_tenant(tenant)
        .where('created_at >= ?', days.days.ago)
        .group("DATE(created_at)")
        .count
        .transform_keys { |date| Date.parse(date) }
    end
  end
  
  # Instance methods
  
  # Check if this is a critical error (blocks deployment)
  def critical?
    error_type.in?(%w[security schema])
  end
  
  # Check if this is an accessibility error
  def accessibility_issue?
    error_type == 'color_contrast'
  end
  
  # Check if this error was automatically fixed
  def auto_fixed?
    auto_fixed
  end
  
  # Get the theme generation this error belongs to
  # @return [ThemeGeneration]
  def generation
    theme_generation
  end
  
  # Get human-readable error description
  # @return [String]
  def description
    "#{error_type.titleize}: #{error_message}"
  end
  
  # Get the field that caused the error (if available)
  # @return [String, nil]
  def affected_field
    field_path
  end
end
