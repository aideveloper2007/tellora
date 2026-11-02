# frozen_string_literal: true

# ThemeRefinement tracks incremental changes to themes, enabling surgical
# modifications without full regeneration and maintaining version history.
#
# Purpose in Enterprise Architecture:
# - Support incremental refinements ("make buttons darker")
# - Track exactly what changed (not full regeneration)
# - Enable rollback to previous versions
# - Prevent drift from original design intent
# - Build history of user preferences per tenant
#
# Example Flow:
#   User: "Make the buttons darker"
#   System: Identifies change → colors.accent only
#   ThemeRefinement: Records old value, new value, user request
#   Result: Only accent color changed, everything else preserved
#
class ThemeRefinement < ApplicationRecord
  # Validations
  validates :tenant, presence: true
  validates :theme_id, presence: true
  validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :user_request, presence: true
  
  # Scopes for version management
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }
  scope :for_theme, ->(theme_id) { where(theme_id: theme_id) }
  scope :applied, -> { where(applied: true) }
  scope :pending, -> { where(applied: false) }
  scope :recent, ->(limit = 10) { order(version: :desc).limit(limit) }
  scope :by_version, -> { order(:version) }
  
  # Class methods for version management
  class << self
    # Get refinement history for a theme
    # Shows all incremental changes over time
    #
    # @param theme_id [Integer] Theme ID
    # @return [ActiveRecord::Relation]
    def history_for_theme(theme_id)
      for_theme(theme_id).applied.by_version
    end
    
    # Get next version number for a theme
    # @param theme_id [Integer] Theme ID
    # @return [Integer]
    def next_version(theme_id)
      max_version = for_theme(theme_id).maximum(:version) || 0
      max_version + 1
    end
    
    # Get user preference patterns
    # Identifies common refinement requests per tenant
    #
    # @param tenant [String] Tenant identifier
    # @return [Hash] Change category => count
    def preference_patterns(tenant)
      for_tenant(tenant)
        .applied
        .pluck(:changes_made)
        .flat_map(&:keys)
        .group_by(&:itself)
        .transform_values(&:count)
        .sort_by { |_, count| -count }
        .first(10)
        .to_h
    end
    
    # Calculate total fields changed across all refinements
    # Helps measure complexity of changes
    #
    # @param theme_id [Integer] Theme ID
    # @return [Integer]
    def total_changes_for_theme(theme_id)
      for_theme(theme_id)
        .applied
        .sum(:fields_changed_count)
    end
    
    # Rollback to a specific version
    # Gets the state at that version by replaying changes
    #
    # @param theme_id [Integer] Theme ID
    # @param target_version [Integer] Version to rollback to
    # @return [Hash] Theme state at that version
    def rollback_to_version(theme_id, target_version)
      refinements = for_theme(theme_id)
                      .applied
                      .where('version <= ?', target_version)
                      .by_version
      
      # Start with base theme and apply refinements in order
      theme_state = {}
      refinements.each do |refinement|
        theme_state.deep_merge!(refinement.new_values)
      end
      
      theme_state
    end
  end
  
  # Instance methods
  
  # Check if refinement has been applied
  def applied?
    applied
  end
  
  # Apply this refinement
  # Marks as applied and returns new values
  #
  # @return [Hash] New theme values
  def apply!
    update!(applied: true)
    new_values
  end
  
  # Revert this refinement
  # Marks as not applied and returns previous values
  #
  # @return [Hash] Previous theme values
  def revert!
    update!(applied: false)
    previous_values
  end
  
  # Get summary of what changed
  # @return [String] Human-readable change description
  def change_summary
    return "No changes" if changes_made.blank?
    
    changed_fields = changes_made.keys
    "Changed #{fields_changed_count} field(s): #{changed_fields.join(', ')}"
  end
  
  # Get specific field changes
  # @param field [String] Field path (e.g., 'colors.accent')
  # @return [Hash] { old: value, new: value }
  def field_change(field)
    return nil unless changes_made.key?(field)
    
    {
      old: previous_values[field],
      new: new_values[field]
    }
  end
  
  # Check if this refinement changed colors
  def color_change?
    changes_made.keys.any? { |key| key.start_with?('colors.') }
  end
  
  # Check if this refinement changed typography
  def typography_change?
    changes_made.keys.any? { |key| key.start_with?('typography.') }
  end
  
  # Check if this refinement changed layout
  def layout_change?
    changes_made.keys.any? { |key| key.start_with?('layout.') }
  end
  
  # Get refinement history for this theme
  # @return [ActiveRecord::Relation]
  def theme_history
    self.class.history_for_theme(theme_id)
  end
  
  # Get previous refinement version
  # @return [ThemeRefinement, nil]
  def previous_version
    return nil if version <= 1
    
    self.class
      .for_theme(theme_id)
      .where('version < ?', version)
      .order(version: :desc)
      .first
  end
  
  # Get next refinement version
  # @return [ThemeRefinement, nil]
  def next_version
    self.class
      .for_theme(theme_id)
      .where('version > ?', version)
      .order(:version)
      .first
  end
  
  # Calculate percentage of theme changed
  # @param total_fields [Integer] Total fields in theme
  # @return [Float] Percentage changed
  def change_percentage(total_fields = 50)
    return 0.0 if fields_changed_count.zero?
    
    ((fields_changed_count.to_f / total_fields) * 100).round(2)
  end
end
