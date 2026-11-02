# frozen_string_literal: true

class GenaiThemesController < ApplicationController
  skip_before_action :set_current_store
  before_action :set_genai_service, except: [:index]
  before_action :ensure_theme_images_table, except: [:index]


  # Landing page with options
  def index
    @onboarding = params[:onboarding] == 'true'
    
    @api_status = begin
      uri = URI("#{ENV.fetch("GENAI_SERVICE_URL", "http://localhost:8000")}/")
      response = Net::HTTP.get_response(uri)
      response.code == "200" ? { 'status' => 'online' } : { 'status' => 'error' }
    rescue => e
      { 'status' => 'error', 'message' => e.message }
    end
  end

  # GET /genai_themes/chat


  # Chat interface
  def chat
    session[:genai_conversation_id] ||= begin
      result = @genai_service.start_conversation
      result['conversation_id']
    rescue StandardError => e
      flash.now[:error] = "Failed to start conversation: #{e.message}"
      nil
    end

    @conversation_id = session[:genai_conversation_id]
  end

  # POST /genai_themes/send_message
  # Send a chat message (AJAX)
  def send_message
    message = params[:message]
    context = params[:context] || {}
    use_real_llm = params[:use_real_llm] # Get toggle state from frontend
    
    Rails.logger.info "GenAI send_message: message=#{message}, conversation_id=#{session[:genai_conversation_id]}, use_real_llm=#{use_real_llm}"

    begin
      result = @genai_service.send_message(message: message, context: context, use_real_llm: use_real_llm)
    rescue StandardError => e
      # If conversation not found, start a new one and retry
      if e.message.include?('not found') || e.message.include?('CONVERSATION_NOT_FOUND')
        Rails.logger.info "Conversation not found, starting new one..."
        start_result = @genai_service.start_conversation(use_real_llm: use_real_llm)
        session[:genai_conversation_id] = start_result['conversation_id']
        @genai_service.instance_variable_set(:@conversation_id, session[:genai_conversation_id])
        
        # Retry sending the message
        result = @genai_service.send_message(message: message, context: context, use_real_llm: use_real_llm)
      else
        raise
      end
    end
    
    Rails.logger.info "GenAI send_message result: #{result.inspect}"

    render json: {
      success: true,
      data: result
    }
  rescue StandardError => e
    Rails.logger.error "GenAI send_message error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  # POST /genai_themes/upload_prd
  # Upload PRD document (AJAX)
  def upload_prd
    unless params[:file].present?
      return render json: {
        success: false,
        error: 'No file provided'
      }, status: :unprocessable_entity
    end

    # Save uploaded file temporarily
    file = params[:file]
    temp_path = Rails.root.join('tmp', 'uploads', file.original_filename)
    FileUtils.mkdir_p(File.dirname(temp_path))
    File.open(temp_path, 'wb') { |f| f.write(file.read) }

    use_real_llm = params[:use_real_llm]
    
    begin
      result = @genai_service.upload_prd(file_path: temp_path, use_real_llm: use_real_llm)
    rescue StandardError => e
      # If conversation not found, start a new one and retry
      if e.message.include?('not found') || e.message.include?('CONVERSATION_NOT_FOUND')
        Rails.logger.info "Conversation not found during PRD upload, starting new one..."
        start_result = @genai_service.start_conversation(use_real_llm: use_real_llm)
        session[:genai_conversation_id] = start_result['conversation_id']
        @genai_service.instance_variable_set(:@conversation_id, session[:genai_conversation_id])
        
        # Retry uploading the PRD
        result = @genai_service.upload_prd(file_path: temp_path, use_real_llm: use_real_llm)
      else
        raise
      end
    end

    # Clean up temp file
    File.delete(temp_path) if File.exist?(temp_path)

    render json: {
      success: true,
      data: result
    }
  rescue StandardError => e
    # Ensure temp file cleanup even on error
    File.delete(temp_path) if temp_path && File.exist?(temp_path)
    
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  # POST /genai_themes/generate
  # Generate theme from requirements
  def generate
    store_type = params[:store_type] || 'general'
    template = params[:template]
    requirements = params[:requirements] || {}
    use_real_llm = params[:use_real_llm]

    # Add store name from tenant if not provided
    requirements['store_name'] ||= current_tenant.name

    result = @genai_service.generate_theme(
      store_type: store_type,
      template: template,
      requirements: requirements,
      use_real_llm: use_real_llm
    )

    # Store theme_id in session
    session[:current_theme_id] = result['theme_id']

    render json: {
      success: true,
      theme_id: result['theme_id'],
      data: result
    }
  rescue StandardError => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  # GET /genai_themes/status/:theme_id
  # Check theme generation status (AJAX)
  def status
    theme_id = params[:id] || params[:theme_id] || session[:current_theme_id]

    unless theme_id
      return render json: {
        success: false,
        error: 'No theme ID provided'
      }, status: :unprocessable_entity
    end

    result = @genai_service.get_theme_status(theme_id: theme_id)

    render json: {
      success: true,
      data: result
    }
  rescue StandardError => e
    Rails.logger.error "Status check error: #{e.message}"
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  # GET /genai_themes/preview/:theme_id
  # Preview generated theme
  def preview
    Rails.logger.info "=== PREVIEW ACTION STARTING ==="
    Rails.logger.info "Params: #{params.inspect}"
    
    @theme_id = params[:id] || params[:theme_id] || session[:current_theme_id]
    Rails.logger.info "Theme ID: #{@theme_id}"
    
    unless @theme_id
      flash[:error] = 'No theme to preview'
      return redirect_to genai_themes_path
    end

    result = @genai_service.get_theme_status(theme_id: @theme_id)
    Rails.logger.info "API Result status: #{result['status']}"

    if result['status'] == 'completed'
      theme_data = result['theme_data']
      
      # Transform API response to match view expectations
      @theme = {
        'theme_id' => @theme_id,
        'color_palette' => theme_data['colors'] || {},
        'typography' => {
          'heading' => {
            'family' => theme_data.dig('typography', 'heading_font'),
            'size' => '2rem',
            'weight' => theme_data.dig('typography', 'heading_weight')
          },
          'body' => {
            'family' => theme_data.dig('typography', 'body_font'),
            'size' => '1rem',
            'weight' => theme_data.dig('typography', 'body_weight')
          }
        },
        'layout' => theme_data['layout'] || {},
        'components' => theme_data['components'] || {},
        'images' => theme_data['images'] || {},
        'css' => theme_data['css'] || '',
        'metadata' => theme_data['metadata'] || {},
        'generated_at' => theme_data.dig('metadata', 'generated_at') ? Time.at(theme_data['metadata']['generated_at']).to_s : nil,
        'template_used' => theme_data.dig('metadata', 'template'),
        'validation_results' => {
          'is_valid' => result.dig('validation_report', 'valid'),
          'score' => result.dig('validation_report', 'overall_score'),
          'issues' => result.dig('validation_report', 'issues') || []
        }
      }
      Rails.logger.info "Theme prepared for view with images: #{@theme['images'].present?}"


    else
      flash[:error] = "Theme not ready. Status: #{result['status']}"
      redirect_to chat_genai_themes_path
    end
  rescue StandardError => e
    Rails.logger.error "Preview error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    flash[:error] = "Failed to load theme: #{e.message}"
    redirect_to genai_themes_path
  end
  def refine
  # POST /genai_themes/:id/refine
    theme_id = params[:id] || params[:theme_id]
    feedback = params[:feedback]
    
    Rails.logger.info "Refining theme #{theme_id} with feedback: #{feedback}"
    
    # Call the refine API
    result = @genai_service.refine_theme(
      theme_id: theme_id,
      feedback: feedback,
    )
    
    # Return new theme_id for polling
    render json: {
      success: true,
      theme_id: result['theme_id'],
      message: 'Refinement started'
    }
  rescue StandardError => e
    Rails.logger.error "Refine error: #{e.message}"
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  # POST /genai_themes/apply
  # POST /genai_themes/:id/apply
  # Apply theme to Spree store (Phase 4 MVP)
  def apply
    theme_id = params[:id] || params[:theme_id]
    
    # Get theme data from FastAPI
    result = @genai_service.get_theme_status(theme_id: theme_id)
    
    unless result['status'] == 'completed'
      return render json: {
        success: false,
        error: 'Theme is not completed yet'
      }, status: :unprocessable_entity
    end

    # Phase 4: Actually apply theme to Spree
    begin
      # 1. Create Spree::Themes::GenAI record
      spree_theme = Spree::Themes::GenAi.create_from_api_response(
        result['theme_data'],
        current_store,
        session[:genai_conversation_id]
      )
      
      # 2. Download and attach images
      if result['theme_data']['images'].present?
        ThemeImageManager.new(spree_theme).download_and_attach_images(
          result['theme_data']['images']
        )
      end
      
      # 3. Mark as ready (but not default yet - that's a separate action)
      spree_theme.update!(ready: true)
      
      Rails.logger.info "Theme applied successfully: #{spree_theme.id} (#{spree_theme.name})"
      
      # 4. Fill an empty store with AI-generated sample products (runs in Sidekiq)
      enqueue_sample_products(result['theme_data'])
      
      render json: {
        success: true,
        message: 'Theme created and ready to activate!',
        theme_id: theme_id,
        spree_theme_id: spree_theme.id,
        preview_url: preview_genai_theme_path(spree_theme)
      }
    rescue StandardError => e
      Rails.logger.error "Failed to apply theme: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      render json: {
        success: false,
        error: "Failed to apply theme: #{e.message}"
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end
  
  # POST /genai_themes/:id/activate
  # Activate theme (set as default for store)
  def activate
    theme_id = params[:id]
    
    # Try to find by Spree theme ID first, then by matching preferences
    spree_theme = if theme_id.match?(/^\d+$/)
      # Numeric ID - Spree theme ID
      Spree::Theme.find(theme_id)
    else
      # FastAPI theme_id - find most recent matching theme
      # Get the theme data from FastAPI
      result = @genai_service.get_theme_status(theme_id: theme_id)
      
      # Find the Spree theme that was created from this FastAPI theme
      # Match by conversation_id or get the most recent GenAI theme
      conversation_id = result.dig('theme_data', 'metadata', 'conversation_id')
      
      if conversation_id
        Spree::Theme.where(type: 'Spree::Themes::GenAi')
                   .where("preferences @> ?", { conversation_id: conversation_id }.to_json)
                   .order(created_at: :desc)
                   .first
      else
        # Fallback: get most recent GenAI theme
        Spree::Theme.where(type: 'Spree::Themes::GenAi')
                   .order(created_at: :desc)
                   .first
      end
    end
    
    unless spree_theme
      return render json: {
        success: false,
        error: 'Theme not found. Please apply the theme first.'
      }, status: :not_found
    end
    
    # Deactivate current default theme
    current_store.themes.where(default: true).update_all(default: false)
    
    # Activate this theme
    spree_theme.update!(default: true)
    
    render json: {
      success: true,
      message: 'Theme activated! Your store is now using the AI-generated theme.',
      theme_id: spree_theme.id
    }
  rescue StandardError => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end
  
  # POST /genai_themes/:id/deactivate
  # Deactivate GenAI theme and return to default Spree theme
  def deactivate
    theme_id = params[:id]
    
    # Find the GenAI theme
    spree_theme = current_store.themes.find_by(id: theme_id, type: 'Spree::Themes::GenAi')
    
    unless spree_theme
      return render json: {
        success: false,
        error: 'Theme not found.'
      }, status: :not_found
    end
    
    # Deactivate this theme
    spree_theme.update!(default: false)
    
    # Find any non-GenAI theme to activate (Spree's default theme)
    default_theme = current_store.themes.where.not(type: 'Spree::Themes::GenAi').first
    
    # If no default theme exists, just leave GenAI theme deactivated
    # Spree will fall back to its built-in default rendering
    if default_theme
      default_theme.update!(default: true)
      theme_message = "Returned to #{default_theme.name} theme successfully."
    else
      theme_message = 'GenAI theme deactivated. Store using default rendering.'
    end
    
    render json: {
      success: true,
      message: theme_message,
      theme_id: default_theme&.id
    }
  rescue StandardError => e
    Rails.logger.error "Deactivate theme error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  private

  # Queue sample products for this store. Never fails the theme apply.
  def enqueue_sample_products(theme_data)
    store_type = theme_data&.dig('metadata', 'store_type').presence ||
                 theme_data&.dig('store_type').presence ||
                 'general'
    SampleProductsJob.perform_async(Apartment::Tenant.current, current_store&.id, store_type)
    Rails.logger.info "Queued sample products for store type '#{store_type}'"
  rescue StandardError => e
    Rails.logger.error "Could not queue sample products: #{e.class} - #{e.message}"
  end

  def set_genai_service
    Rails.logger.info "=== SET_GENAI_SERVICE CALLED FOR ACTION: #{action_name} ==="
    
    tenant = current_tenant_for_genai
    Rails.logger.info "Tenant: #{tenant.inspect}"
    
    user = current_user_for_genai
    Rails.logger.info "User: #{user.inspect}"
    
    @genai_service = GenaiThemeService.new(tenant_id: tenant[:subdomain], user_id: user[:id])
    Rails.logger.info "Service initialized successfully"
    
    if session[:genai_conversation_id]
      @genai_service.instance_variable_set(:@conversation_id, session[:genai_conversation_id])
    end
  rescue => e
    Rails.logger.error "=== ERROR IN SET_GENAI_SERVICE: #{e.class} - #{e.message} ==="
    Rails.logger.error e.backtrace.first(10).join("\n")
    flash[:error] = "Service initialization failed: #{e.message}"
    redirect_to genai_themes_path and return
  end



  def create_or_update_spree_theme(theme_data)
    # Find or create theme
    theme = Spree::Theme.find_or_initialize_by(
      name: "GenAI Theme - #{Time.current.strftime('%Y%m%d_%H%M%S')}"
    )

    # Store theme data in preferences column (JSON)
    theme.preferences = {
      genai_generated: true,
      generated_at: Time.current.iso8601,
      colors: theme_data['colors'],
      typography: theme_data['typography'],
      layout: theme_data['layout'],
      components: theme_data['components'],
      css: theme_data['css'],
      metadata: theme_data['metadata']
    }

    theme.save
    theme
  end

  def current_tenant_for_genai
    if Rails.env.development? && !current_user
      # Development mode without authentication
      { subdomain: 'dev_store', name: 'Development Store' }
    else
      @current_tenant ||= begin
        tenant_subdomain = Apartment::Tenant.current || 'default'
        { subdomain: tenant_subdomain, name: 'My Store' }
      end
    end
  end
  
  def current_user_for_genai
    if Rails.env.development? && !current_user
      # Development mode without authentication
      { id: 'dev_user_123', email: 'dev@example.com' }
    else
      { id: current_user.id, email: current_user.email }
    end
  end
  
  def current_tenant
    @current_tenant ||= Apartment::Tenant.current
    # If using ActsAsTenant or similar, adjust accordingly
    # For now, return a mock object for development
    OpenStruct.new(
      subdomain: Apartment::Tenant.current || 'default',
      name: 'My Store'
    )
  end
  
  def disable_http_caching
    Rails.logger.debug "disable_http_caching called"
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  rescue => e
    Rails.logger.error "ERROR in disable_http_caching: #{e.message}"
  end
  
  # Lazy migration: Create theme_images table on-demand for this tenant
  def ensure_theme_images_table
    return if ActiveRecord::Base.connection.table_exists?('theme_images')
    
    Rails.logger.info "=== Creating theme_images table for tenant: #{Apartment::Tenant.current} ==="
    
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Base.connection.create_table :theme_images do |t|
        t.references :theme, foreign_key: { to_table: :spree_themes }, null: false
        t.string :section, null: false
        t.string :source_url
        t.string :source_attribution
        t.text :metadata
        t.timestamps
      end
      
      ActiveRecord::Base.connection.add_index :theme_images, [:theme_id, :section], unique: true
    end
    
    Rails.logger.info "=== theme_images table created successfully ==="
  rescue => e
    Rails.logger.error "=== ERROR creating theme_images table: #{e.message} ==="
    # Don't fail the request, just log the error
  end
end