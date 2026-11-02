class UpdateConversationEmbeddingsForFlexibleDimensions < ActiveRecord::Migration[8.0]
  def up
    # Only run in public schema (not tenants) - this is a global table
    return unless Apartment::Tenant.current == 'public'
    
    # Check if table exists
    return unless table_exists?(:conversation_embeddings)
    
    # Drop the existing vector column with fixed 1536 dimensions
    execute "ALTER TABLE conversation_embeddings DROP COLUMN IF EXISTS embedding;"
    
    # Add new vector column without dimension constraint
    # This allows both 1536 (OpenAI) and 384 (sentence-transformers) embeddings
    execute "ALTER TABLE conversation_embeddings ADD COLUMN embedding vector;"
    
    # Add columns to track embedding provider and dimensions
    add_column :conversation_embeddings, :embedding_provider, :string unless column_exists?(:conversation_embeddings, :embedding_provider)
    add_column :conversation_embeddings, :embedding_dimensions, :integer unless column_exists?(:conversation_embeddings, :embedding_dimensions)
  end
  
  def down
    return unless Apartment::Tenant.current == 'public'
    return unless table_exists?(:conversation_embeddings)
    
    remove_column :conversation_embeddings, :embedding_dimensions if column_exists?(:conversation_embeddings, :embedding_dimensions)
    remove_column :conversation_embeddings, :embedding_provider if column_exists?(:conversation_embeddings, :embedding_provider)
    execute "ALTER TABLE conversation_embeddings DROP COLUMN IF EXISTS embedding;"
    execute "ALTER TABLE conversation_embeddings ADD COLUMN embedding vector(1536);"
  end
end
