# frozen_string_literal: true

# ThemeGeneration tracks all AI theme generation attempts with quality metrics,
# cost tracking, and performance data.
#
# Purpose in Enterprise Architecture:
# - Track every generation attempt for audit trail
# - Monitor quality scores and identify improvement areas
# - Track costs per tenant and set usage limits
# - Enable A/B testing between different prompts/models
# - Learn from successful vs failed generations
#
# Status Flow:
#   'pending' → 'success' → 'validated' → 'deployed'
#   'pending' → 'failed' → (retry with feedback)
#   'pending' → 'rejected' (validation failed, no retry)
#
class ThemeGeneration < ApplicationRecord
  # Associations
  has_many :validation_errors, class_name: 'ThemeValidationError', dependent: :destroy
  
  # Validations
  validates :tenant, presence: true
  validates :conversation_id, presence: true
  validates :attempt_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status, presence: true, inclusion: { 
    in: %w[pending success failed validated rejected deployed],
    message: "%{value} is not a valid status"
  }
  validates :quality_score, numericality: { 
    only_integer: true, 
    greater_than_or_equal_to: 0, 
    less_than_or_equal_to: 100,
    allow_nil: true
  }
  validates :llm_provider, inclusion: { in: %w[claude mock openai], allow_nil: true }
  
  # Scopes for analytics and monitoring
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :successful, -> { where(status: ['success', 'validated', 'deployed']) }
  scope :failed, -> { where(status: ['failed', 'rejected']) }
  scope :high_quality, -> { where('quality_score >= ?', 80) }
  scope :low_quality, -> { where('quality_score < ?', 70) }
  scope :recent, ->(days = 7) { where('created_at >= ?', days.days.ago) }
  scope :by_provider, ->(provider) { where(llm_provider: provider) }
  scope :expensive, ->(threshold = 0.50) { where('cost_usd > ?', threshold) }
  
  # Class methods for analytics
  class << self
    # Calculate average quality score for a tenant
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to look back
    # @return [Float]
    def average_quality(tenant, days: 30)
      for_tenant(tenant)
        .successful
        .recent(days)
        .average(:quality_score)
        .to_f
        .round(2)
    end
    
    # Calculate total cost for a tenant
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to look back
    # @return [Float]
    def total_cost(tenant, days: 30)
      for_tenant(tenant)
        .recent(days)
        .sum(:cost_usd)
        .to_f
        .round(2)
    end
    
    # Get success rate for a tenant
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to look back
    # @return [Float] Percentage (0-100)
    def success_rate(tenant, days: 30)
      total = for_tenant(tenant).recent(days).count
      return 0.0 if total.zero?
      
      successful_count = for_tenant(tenant).successful.recent(days).count
      ((successful_count.to_f / total) * 100).round(2)
    end
    
    # Get average generation time
    # @param tenant [String] Tenant identifier
    # @param days [Integer] Days to look back
    # @return [Integer] Milliseconds
    def average_generation_time(tenant, days: 30)
      for_tenant(tenant)
        .successful
        .recent(days)
        .average(:generation_time_ms)
        .to_i
    end
    
    # Compare providers (Claude vs Mock)
    # @param tenant [String] Tenant identifier
    # @return [Hash] Comparison metrics
    def compare_providers(tenant)
      %w[claude mock].map do |provider|
        generations = for_tenant(tenant).by_provider(provider).successful
        
        {
          provider: provider,
          count: generations.count,
          avg_quality: generations.average(:quality_score).to_f.round(2),
          avg_cost: generations.average(:cost_usd).to_f.round(4),
          avg_time: generations.average(:generation_time_ms).to_i
        }
      end
    end
  end
  
  # Instance methods
  
  # Check if this generation passed validation
  def validated?
    status.in?(%w[validated deployed])
  end
  
  # Check if generation failed
  def failed?
    status.in?(%w[failed rejected])
  end
  
  # Check if this is the first attempt
  def first_attempt?
    attempt_number == 1
  end
  
  # Check if quality meets minimum threshold
  # @param threshold [Integer] Minimum quality score (default 70)
  # @return [Boolean]
  def meets_quality_threshold?(threshold = 70)
    quality_score.present? && quality_score >= threshold
  end
  
  # Check if cost is within acceptable range
  # @param max_cost [Float] Maximum acceptable cost in USD
  # @return [Boolean]
  def within_budget?(max_cost = 0.30)
    cost_usd.present? && cost_usd <= max_cost
  end
  
  # Get all attempts for this conversation
  # @return [ActiveRecord::Relation]
  def all_attempts
    self.class
      .for_tenant(tenant)
      .for_conversation(conversation_id)
      .order(:attempt_number)
  end
  
  # Get previous attempt (if any)
  # @return [ThemeGeneration, nil]
  def previous_attempt
    return nil if first_attempt?
    
    self.class
      .for_tenant(tenant)
      .for_conversation(conversation_id)
      .where('attempt_number < ?', attempt_number)
      .order(attempt_number: :desc)
      .first
  end
  
  # Mark as validated with quality score
  # @param score [Integer] Quality score (0-100)
  def mark_validated!(score)
    update!(
      status: 'validated',
      quality_score: score
    )
  end
  
  # Mark as failed with error tracking
  def mark_failed!
    update!(status: 'failed')
  end
  
  # Mark as deployed (theme activated by merchant)
  def mark_deployed!
    update!(status: 'deployed')
  end
  
  # Get validation error summary
  # @return [Hash] Summary of validation errors
  def validation_error_summary
    validation_errors.group(:error_type).count
  end
  
  # Calculate cost efficiency (quality per dollar)
  # @return [Float] Quality score per cent spent
  def cost_efficiency
    return 0.0 if cost_usd.nil? || cost_usd.zero? || quality_score.nil?
    
    (quality_score / (cost_usd * 100)).round(2)
  end
end
