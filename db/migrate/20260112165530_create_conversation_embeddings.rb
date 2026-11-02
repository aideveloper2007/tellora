class CreateConversationEmbeddings < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_embeddings do |t|
      t.string :tenant, null: false
      t.string :conversation_id, null: false
      t.integer :message_index, null: false
      t.text :message_content, null: false
      t.string :role, null: false # 'user' or 'assistant'
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    # Add vector column using execute (pgvector gem doesn't register in Rails 8)
    execute <<-SQL
      ALTER TABLE conversation_embeddings 
      ADD COLUMN embedding vector(1536);
    SQL
    
    # Indexes for efficient queries
    add_index :conversation_embeddings, [:tenant, :conversation_id]
    add_index :conversation_embeddings, :tenant
    add_index :conversation_embeddings, :conversation_id
    
    # GIN index for JSONB metadata
    add_index :conversation_embeddings, :metadata, using: :gin
  end
end
