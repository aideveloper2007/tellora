class CreateThemeTrackingTables < ActiveRecord::Migration[8.0]
  def change
    # Theme generations history - tracks all AI theme generation attempts
    create_table :theme_generations do |t|
      t.string :tenant, null: false
      t.string :conversation_id, null: false
      t.integer :attempt_number, default: 1
      t.string :store_type
      t.jsonb :requirements, default: {}
      t.jsonb :theme_data, default: {}
      t.string :status # 'success', 'failed', 'validated', 'rejected'
      t.integer :quality_score # 0-100
      t.decimal :cost_tokens, precision: 10, scale: 2
      t.decimal :cost_usd, precision: 10, scale: 4
      t.integer :generation_time_ms
      t.string :llm_provider # 'claude', 'mock'
      t.string :llm_model # 'claude-3-5-sonnet-20241022'
      
      t.timestamps
    end
    
    add_index :theme_generations, [:tenant, :conversation_id]
    add_index :theme_generations, :tenant
    add_index :theme_generations, :status
    add_index :theme_generations, :created_at
    
    # Theme validation errors - learn from validation failures
    create_table :theme_validation_errors do |t|
      t.references :theme_generation, null: false, foreign_key: true
      t.string :tenant, null: false
      t.string :error_type # 'schema', 'color_contrast', 'font', 'css', 'layout', 'security'
      t.string :field_path # e.g., 'colors.primary', 'typography.heading.fontFamily'
      t.text :error_message
      t.jsonb :error_details, default: {}
      t.boolean :auto_fixed, default: false
      
      t.timestamps
    end
    
    add_index :theme_validation_errors, :tenant
    add_index :theme_validation_errors, :error_type
    add_index :theme_validation_errors, [:tenant, :error_type]
    
    # Frontend runtime errors - monitor production theme issues
    create_table :theme_frontend_errors do |t|
      t.string :tenant, null: false
      t.integer :theme_id
      t.string :error_type # 'css_error', 'image_404', 'layout_overflow', 'js_error'
      t.text :error_message
      t.string :page_url
      t.string :browser
      t.string :viewport_size
      t.jsonb :error_details, default: {}
      t.text :screenshot_url
      t.boolean :resolved, default: false
      t.text :resolution_notes
      
      t.timestamps
    end
    
    add_index :theme_frontend_errors, :tenant
    add_index :theme_frontend_errors, :theme_id
    add_index :theme_frontend_errors, :error_type
    add_index :theme_frontend_errors, :resolved
    
    # Theme refinements - track incremental changes
    create_table :theme_refinements do |t|
      t.string :tenant, null: false
      t.integer :theme_id, null: false
      t.integer :version, default: 1
      t.text :user_request
      t.jsonb :changes_made, default: {}
      t.jsonb :previous_values, default: {}
      t.jsonb :new_values, default: {}
      t.integer :fields_changed_count
      t.boolean :applied, default: false
      
      t.timestamps
    end
    
    add_index :theme_refinements, [:tenant, :theme_id]
    add_index :theme_refinements, :tenant
    add_index :theme_refinements, :theme_id
    add_index :theme_refinements, :version
    
    # Merchant feedback - learn from user satisfaction
    create_table :merchant_feedback do |t|
      t.string :tenant, null: false
      t.integer :theme_id
      t.string :conversation_id
      t.integer :rating # 1-5 stars
      t.text :feedback_text
      t.jsonb :issues_reported, default: []
      t.jsonb :liked_features, default: []
      t.string :feedback_type # 'positive', 'negative', 'neutral'
      t.boolean :theme_activated, default: false
      
      t.timestamps
    end
    
    add_index :merchant_feedback, :tenant
    add_index :merchant_feedback, :theme_id
    add_index :merchant_feedback, :rating
    add_index :merchant_feedback, :feedback_type
  end
end
