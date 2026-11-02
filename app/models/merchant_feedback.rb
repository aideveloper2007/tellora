# frozen_string_literal: true

# MerchantFeedback captures user satisfaction data to enable continuous
# learning and improvement of the AI theme generation system.
#
# Purpose in Enterprise Architecture:
# - Learn from what merchants like/dislike
# - Identify patterns in successful vs unsuccessful themes
# - Adjust AI prompting based on feedback
# - Measure overall system satisfaction
# - Build merchant-specific preferences
#
# Rating System:
#   5 stars - Excellent (theme activated immediately)
#   4 stars - Good (minor tweaks needed)
#   3 stars - Okay (several refinements needed)
#   2 stars - Poor (major issues, requires regeneration)
#   1 star - Terrible (completely off-target)
#
class MerchantFeedback < ApplicationRecord
  self.table_name = 'merchant_feedback'
  
  # Validations
  validates :tenant, presence: true
  validates :rating, presence: true, numericality: { 
    only_integer: true, 
    greater_than_or_equal_to: 1, 
    less_than_or_equal_to: 5 
  }
  validates :feedback_type, inclusion: {
    in: %w[positive negative neutral],
    allow_nil: true
  }
  
  # Callbacks
  before_validation :set_feedback_type
  
  # Scopes for analytics
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }
  scope :for_theme, ->(theme_id) { where(theme_id: theme_id) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :positive, -> { where(feedback_type: 'positive') }
  scope :negative, -> { where(feedback_type: 'negative') }
  scope :neutral, -> { where(feedback_type: 'neutral') }
  scope :high_rated, -> { where('rating >= ?', 4) }
  scope :low_rated, -> { where('rating <= ?', 2) }
  scope :activated, -> { where(theme_activated: true) }
  scope :not_activated, -> { where(theme_activated: false) }
  scope :recent, ->(days = 30) { where('created_at >= ?', days.days.ago) }
  
  # Class methods for learning and analytics
  class << self
    # Calculate average satisfaction score
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to look back
    # @return [Float] Average rating (1-5)
    def satisfaction_score(tenant, days: 30)
      for_tenant(tenant)
        .recent(days)
        .average(:rating)
        .to_f
        .round(2)
    end
    
    # Get Net Promoter Score (NPS)
    # Promoters (5 stars) - Detractors (1-2 stars)
    #
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to look back
    # @return [Float] NPS score (-100 to 100)
    def nps_score(tenant, days: 30)
      feedback = for_tenant(tenant).recent(days)
      total = feedback.count
      return 0.0 if total.zero?
      
      promoters = feedback.where(rating: 5).count
      detractors = feedback.where(rating: [1, 2]).count
      
      (((promoters - detractors).to_f / total) * 100).round(2)
    end
    
    # Get activation rate (themes that were activated)
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to look back
    # @return [Float] Percentage (0-100)
    def activation_rate(tenant, days: 30)
      total = for_tenant(tenant).recent(days).count
      return 0.0 if total.zero?
      
      activated_count = for_tenant(tenant).activated.recent(days).count
      ((activated_count.to_f / total) * 100).round(2)
    end
    
    # Get common issues reported
    # Helps identify systemic problems
    #
    # @param tenant [String] Tenant identifier
    # @return [Array<String>] Most common issues
    def common_issues(tenant)
      for_tenant(tenant)
        .negative
        .pluck(:issues_reported)
        .flatten
        .compact
        .group_by(&:itself)
        .transform_values(&:count)
        .sort_by { |_, count| -count }
        .first(5)
        .map(&:first)
    end
    
    # Get most liked features
    # Helps understand what works well
    #
    # @param tenant [String] Tenant identifier
    # @return [Array<String>] Most liked features
    def liked_features(tenant)
      for_tenant(tenant)
        .positive
        .pluck(:liked_features)
        .flatten
        .compact
        .group_by(&:itself)
        .transform_values(&:count)
        .sort_by { |_, count| -count }
        .first(5)
        .map(&:first)
    end
    
    # Build learning insights for AI improvement
    # Analyzes feedback to improve future generations
    #
    # @param tenant [String] Tenant identifier
    # @return [Hash] Insights for system improvement
    def learning_insights(tenant)
      {
        satisfaction_score: satisfaction_score(tenant),
        nps_score: nps_score(tenant),
        activation_rate: activation_rate(tenant),
        common_issues: common_issues(tenant),
        liked_features: liked_features(tenant),
        total_feedback: for_tenant(tenant).recent(30).count,
        positive_feedback: for_tenant(tenant).positive.recent(30).count,
        negative_feedback: for_tenant(tenant).negative.recent(30).count
      }
    end
    
    # Compare themes by average rating
    # Identifies which themes merchants prefer
    #
    # @param tenant [String] Tenant identifier
    # @return [Array<Hash>] Themes sorted by rating
    def top_rated_themes(tenant, limit: 5)
      for_tenant(tenant)
        .where.not(theme_id: nil)
        .group(:theme_id)
        .select('theme_id, 
                 AVG(rating) as avg_rating,
                 COUNT(*) as feedback_count')
        .order('avg_rating DESC')
        .limit(limit)
        .map do |result|
          {
            theme_id: result.theme_id,
            avg_rating: result.avg_rating.to_f.round(2),
            feedback_count: result.feedback_count
          }
        end
    end
  end
  
  # Instance methods
  
  # Check if feedback is positive
  def positive?
    feedback_type == 'positive'
  end
  
  # Check if feedback is negative
  def negative?
    feedback_type == 'negative'
  end
  
  # Check if theme was activated
  def activated?
    theme_activated
  end
  
  # Check if this is a promoter (NPS)
  def promoter?
    rating == 5
  end
  
  # Check if this is a detractor (NPS)
  def detractor?
    rating.in?([1, 2])
  end
  
  # Get emoji representation of rating
  # @return [String]
  def rating_emoji
    case rating
    when 5 then '⭐⭐⭐⭐⭐'
    when 4 then '⭐⭐⭐⭐'
    when 3 then '⭐⭐⭐'
    when 2 then '⭐⭐'
    when 1 then '⭐'
    end
  end
  
  # Get summary of feedback
  # @return [String]
  def summary
    parts = [rating_emoji]
    parts << feedback_text if feedback_text.present?
    parts << "(Activated)" if theme_activated
    parts.join(' - ')
  end
  
  private
  
  # Set feedback type based on rating
  def set_feedback_type
    return if feedback_type.present?
    
    self.feedback_type = case rating
                         when 4..5 then 'positive'
                         when 3 then 'neutral'
                         when 1..2 then 'negative'
                         end
  end
end
