# frozen_string_literal: true

# ThemeFrontendError monitors production runtime errors for deployed themes
# to enable self-healing and prevent merchant-facing issues.
#
# Purpose in Enterprise Architecture:
# - Detect CSS rendering errors in production
# - Monitor broken images (404s)
# - Identify layout issues (overflow, overlapping elements)
# - Track JavaScript errors related to theme
# - Enable automatic fixes or rollback to safe fallback
# - Alert developers to systemic issues
#
# Error Types:
#   - 'css_error': Broken styles, rendering issues
#   - 'image_404': Images not loading
#   - 'layout_overflow': Content overflowing containers
#   - 'js_error': JavaScript errors affecting theme
#
class ThemeFrontendError < ApplicationRecord
  # Validations
  validates :tenant, presence: true
  validates :error_type, presence: true, inclusion: {
    in: %w[css_error image_404 layout_overflow js_error],
    message: "%{value} is not a valid error type"
  }
  validates :error_message, presence: true
  
  # Scopes for monitoring
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }
  scope :for_theme, ->(theme_id) { where(theme_id: theme_id) }
  scope :by_type, ->(type) { where(error_type: type) }
  scope :unresolved, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :recent, ->(hours = 24) { where('created_at >= ?', hours.hours.ago) }
  scope :critical, -> { where(error_type: %w[css_error layout_overflow]) }
  
  # Class methods for monitoring and self-healing
  class << self
    # Get active error count for a theme
    # Used to determine if theme should be auto-disabled
    #
    # @param theme_id [Integer] Theme ID
    # @return [Integer]
    def active_error_count(theme_id)
      for_theme(theme_id).unresolved.count
    end
    
    # Check if theme should be auto-disabled
    # Triggers if critical errors exceed threshold
    #
    # @param theme_id [Integer] Theme ID
    # @param threshold [Integer] Max allowed errors
    # @return [Boolean]
    def should_disable_theme?(theme_id, threshold: 5)
      critical_count = for_theme(theme_id).unresolved.critical.count
      critical_count >= threshold
    end
    
    # Get error summary for a tenant
    # Used for analytics dashboard
    #
    # @param tenant [String] Tenant identifier
    # @param hours [Integer] Hours to look back
    # @return [Hash] Error type => count
    def error_summary(tenant, hours: 24)
      for_tenant(tenant)
        .recent(hours)
        .unresolved
        .group(:error_type)
        .count
    end
    
    # Get themes with most errors (candidates for investigation)
    # @param tenant [String] Tenant identifier
    # @param limit [Integer] Number of themes to return
    # @return [Array<Hash>] Theme IDs with error counts
    def problematic_themes(tenant, limit: 5)
      for_tenant(tenant)
        .unresolved
        .where.not(theme_id: nil)
        .group(:theme_id)
        .count
        .sort_by { |_, count| -count }
        .first(limit)
        .map { |theme_id, count| { theme_id: theme_id, error_count: count } }
    end
    
    # Build analysis report for AI self-healing
    # Converts error data into prompt for Claude to suggest fixes
    #
    # @param theme_id [Integer] Theme ID
    # @return [String] Error analysis for AI
    def build_analysis_for_healing(theme_id)
      errors = for_theme(theme_id).unresolved.recent(24)
      return "No active errors detected." if errors.empty?
      
      analysis = ["Theme Error Analysis:\n"]
      
      errors.group_by(&:error_type).each do |error_type, group_errors|
        analysis << "\n#{error_type.titleize} (#{group_errors.count} occurrences):"
        
        # Show unique error messages
        unique_errors = group_errors.map(&:error_message).uniq.first(3)
        unique_errors.each do |msg|
          analysis << "  - #{msg}"
        end
        
        # Add browser/viewport context
        if error_type.in?(%w[css_error layout_overflow])
          browsers = group_errors.map(&:browser).compact.uniq
          viewports = group_errors.map(&:viewport_size).compact.uniq
          analysis << "    Browsers: #{browsers.join(', ')}" if browsers.any?
          analysis << "    Viewports: #{viewports.join(', ')}" if viewports.any?
        end
      end
      
      analysis.join("\n")
    end
  end
  
  # Instance methods
  
  # Check if this is a critical error requiring immediate action
  def critical?
    error_type.in?(%w[css_error layout_overflow])
  end
  
  # Check if error is unresolved
  def unresolved?
    !resolved
  end
  
  # Mark error as resolved with notes
  # @param notes [String] Resolution details
  def mark_resolved!(notes = nil)
    update!(
      resolved: true,
      resolution_notes: notes || "Auto-resolved via self-healing system"
    )
  end
  
  # Check if error has screenshot for visual debugging
  def has_screenshot?
    screenshot_url.present?
  end
  
  # Get user context (browser + viewport)
  # @return [String]
  def user_context
    context = []
    context << browser if browser.present?
    context << viewport_size if viewport_size.present?
    context.join(' | ')
  end
  
  # Get time since error occurred
  # @return [String] Human-readable duration
  def time_since_error
    time_ago_in_words = ((Time.current - created_at) / 1.minute).to_i
    
    case time_ago_in_words
    when 0..59
      "#{time_ago_in_words} minutes ago"
    when 60..1439
      "#{time_ago_in_words / 60} hours ago"
    else
      "#{time_ago_in_words / 1440} days ago"
    end
  end
  
  # Check if this error affects mobile users
  def mobile_issue?
    viewport_size.present? && viewport_size.to_i < 768
  end
end
