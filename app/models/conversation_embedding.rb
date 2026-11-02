# frozen_string_literal: true

# ConversationEmbedding stores conversation history with vector embeddings
# for semantic search and intelligent context retrieval.
#
# Purpose in Enterprise Architecture:
# - Enable semantic search across past conversations
# - Retrieve relevant context for Claude prompting
# - Maintain conversation history without hitting token limits
# - Support intelligent pruning (keep recent + semantically relevant)
#
# Usage:
#   # Store conversation with embedding
#   ConversationEmbedding.create!(
#     tenant: 'shopxyz',
#     conversation_id: 'conv_123',
#     message_index: 1,
#     message_content: 'I want a jewelry store theme',
#     role: 'user',
#     embedding: vector_from_openai_api
#   )
#
#   # Semantic search for similar conversations
#   ConversationEmbedding.search_similar(tenant, query_embedding, limit: 5)
#
class ConversationEmbedding < ApplicationRecord
  # Validations
  validates :tenant, presence: true
  validates :conversation_id, presence: true
  validates :message_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :message_content, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant system] }
  
  # Scopes for common queries
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :user_messages, -> { where(role: 'user') }
  scope :assistant_messages, -> { where(role: 'assistant') }
  scope :recent, ->(limit = 10) { order(created_at: :desc).limit(limit) }
  scope :by_conversation_order, -> { order(:conversation_id, :message_index) }
  
  # Class methods for semantic search (using pgvector)
  class << self
    # Search for semantically similar conversations
    # Returns conversations ordered by cosine similarity
    #
    # @param tenant [String] Tenant identifier
    # @param query_embedding [Array<Float>] Query vector (1536 dimensions)
    # @param limit [Integer] Number of results to return
    # @return [ActiveRecord::Relation]
    def search_similar(tenant, query_embedding, limit: 5)
      return none if query_embedding.blank?
      
      # pgvector cosine distance search
      # Lower distance = more similar
      where(tenant: tenant)
        .where.not(embedding: nil)
        .order(Arel.sql("embedding <=> '#{format_vector(query_embedding)}'"))
        .limit(limit)
    end
    
    # Get conversation context for a specific conversation
    # Returns all messages in chronological order
    #
    # @param tenant [String] Tenant identifier
    # @param conversation_id [String] Conversation ID
    # @return [ActiveRecord::Relation]
    def conversation_context(tenant, conversation_id)
      for_tenant(tenant)
        .for_conversation(conversation_id)
        .by_conversation_order
    end
    
    # Prune old conversations to manage storage
    # Keeps recent conversations and high-engagement ones
    #
    # @param tenant [String] Tenant identifier
    # @param keep_days [Integer] Days to keep
    def prune_old_conversations(tenant, keep_days: 90)
      cutoff_date = keep_days.days.ago
      
      for_tenant(tenant)
        .where('created_at < ?', cutoff_date)
        .delete_all
    end
    
    private
    
    def format_vector(embedding)
      "[#{embedding.join(',')}]"
    end
  end
  
  # Instance methods
  
  # Check if this is a user's initial request
  def initial_request?
    message_index == 0 && role == 'user'
  end
  
  # Get similarity score to another embedding
  # @param other_embedding [Array<Float>] Vector to compare
  # @return [Float] Cosine similarity (0-1, higher = more similar)
  def similarity_to(other_embedding)
    return 0.0 if embedding.nil? || other_embedding.blank?
    
    # Cosine similarity = 1 - cosine_distance
    result = self.class.connection.execute(
      "SELECT 1 - (embedding <=> '#{self.class.send(:format_vector, other_embedding)}') as similarity 
       FROM conversation_embeddings 
       WHERE id = #{id}"
    )
    
    result.first['similarity'].to_f
  end
  
  # Get the full conversation this message belongs to
  # @return [Array<ConversationEmbedding>]
  def full_conversation
    self.class.conversation_context(tenant, conversation_id)
  end
end
