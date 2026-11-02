class ThemeDesignerController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation, only: [:chat, :upload_prd, :generate_theme, :preview_theme, :publish_theme]
  
  # GET /theme_designer
  def index
    @conversation = current_user.chat_conversations.find_or_create_by!(
      tenant_schema: current_tenant_schema,
      status: 'active'
    )
    
    @messages = @conversation.chat_messages.ordered
    @current_theme = @conversation.latest_theme
  end
  
  # POST /theme_designer/chat
  def chat
    message_content = params[:message]
    
    # Save user message
    user_message = @conversation.chat_messages.create!(
      role: 'user',
      content: message_content,
      message_type: 'text'
    )
    
    # Call GenAI service
    genai_service = GenaiThemeService.new
    response = genai_service.chat(
      conversation_id: @conversation.session_id,
      message: message_content,
      tenant_schema: current_tenant_schema,
      context: build_context
    )
    
    # Save assistant response
    assistant_message = @conversation.chat_messages.create!(
      role: 'assistant',
      content: response['response'],
      message_type: 'text',
      metadata: response['metadata']
    )
    
    render json: {
      message: assistant_message.content,
      message_id: assistant_message.id,
      metadata: assistant_message.metadata
    }
  rescue => e
    Rails.logger.error("Chat error: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end
  
  # POST /theme_designer/upload_prd
  def upload_prd
    uploaded_file = params[:file]
    
    unless uploaded_file
      return render json: { error: 'No file uploaded' }, status: :bad_request
    end
    
    # Save file temporarily
    temp_file = Tempfile.new([uploaded_file.original_filename, File.extname(uploaded_file.original_filename)])
    temp_file.binmode
    temp_file.write(uploaded_file.read)
    temp_file.rewind
    
    # Create PRD document record
    prd_doc = @conversation.prd_documents.create!(
      filename: uploaded_file.original_filename,
      file_type: File.extname(uploaded_file.original_filename)[1..],
      file_size: uploaded_file.size,
      status: 'processing'
    )
    
    # Create message for file upload
    file_message = @conversation.chat_messages.create!(
      role: 'user',
      content: "Uploaded PRD document: #{uploaded_file.original_filename}",
      message_type: 'file_upload',
      metadata: { prd_document_id: prd_doc.id }
    )
    
    # Call GenAI service to parse
    genai_service = GenaiThemeService.new
    result = genai_service.parse_prd(
      file_path: temp_file.path,
      conversation_id: @conversation.session_id,
      tenant_schema: current_tenant_schema
    )
    
    # Update PRD document
    prd_doc.update!(
      extracted_text: result['extracted_text'],
      parsed_requirements: result['parsed_requirements'],
      status: 'completed'
    )
    
    # Create assistant response
    response_text = "I've analyzed your PRD document. Here's what I found:\n\n" + 
                   format_requirements(result['parsed_requirements'])
    
    assistant_message = @conversation.chat_messages.create!(
      role: 'assistant',
      content: response_text,
      message_type: 'text',
      metadata: { prd_document_id: prd_doc.id }
    )
    
    temp_file.close
    temp_file.unlink
    
    render json: {
      message: assistant_message.content,
      prd_document_id: prd_doc.id,
      parsed_requirements: result['parsed_requirements']
    }
  rescue => e
    Rails.logger.error("PRD upload error: #{e.message}")
    prd_doc&.update(status: 'failed')
    temp_file&.close
    temp_file&.unlink
    render json: { error: e.message }, status: :unprocessable_entity
  end
  
  # POST /theme_designer/generate_theme
  def generate_theme
    requirements = params[:requirements] || extract_latest_requirements
    modification_request = params[:modification_request]
    previous_theme = @conversation.latest_theme&.theme_config
    
    # Call GenAI service
    genai_service = GenaiThemeService.new
    result = genai_service.generate_theme(
      conversation_id: @conversation.session_id,
      tenant_schema: current_tenant_schema,
      requirements: requirements,
      previous_theme: previous_theme,
      modification_request: modification_request
    )
    
    # Create theme generation record
    theme = @conversation.theme_generations.create!(
      tenant_schema: current_tenant_schema,
      theme_config: result['theme_config'],
      requirements: requirements,
      status: 'preview',
      notes: result['explanation']
    )
    
    # Create assistant message
    message_content = if modification_request
      "I've updated the theme based on your feedback. #{result['explanation']}"
    else
      "I've generated a new theme for you! #{result['explanation']}"
    end
    
    @conversation.chat_messages.create!(
      role: 'assistant',
      content: message_content,
      message_type: 'theme_generation',
      metadata: { theme_generation_id: theme.id }
    )
    
    render json: {
      theme: theme,
      preview_url: preview_theme_designer_path(theme_id: theme.id),
      explanation: result['explanation']
    }
  rescue => e
    Rails.logger.error("Theme generation error: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end
  
  # GET /theme_designer/preview
  def preview_theme
    theme_id = params[:theme_id]
    @theme = ThemeGeneration.find(theme_id)
    
    render layout: 'theme_preview'
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Theme not found' }, status: :not_found
  end
  
  # POST /theme_designer/publish
  def publish_theme
    theme_id = params[:theme_id]
    theme = ThemeGeneration.find(theme_id)
    
    theme.publish!
    
    @conversation.chat_messages.create!(
      role: 'assistant',
      content: "Great! Your theme has been published and is now live on your store.",
      message_type: 'publish_request',
      metadata: { theme_generation_id: theme.id }
    )
    
    render json: {
      success: true,
      message: 'Theme published successfully',
      theme: theme
    }
  rescue => e
    Rails.logger.error("Theme publish error: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end
  
  # GET /theme_designer/history
  def history
    @conversation = current_user.chat_conversations
      .where(tenant_schema: current_tenant_schema)
      .order(updated_at: :desc)
    
    render json: @conversation
  end
  
  private
  
  def set_conversation
    @conversation = current_user.chat_conversations.find_by!(
      session_id: params[:conversation_id],
      tenant_schema: current_tenant_schema
    )
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conversation not found' }, status: :not_found
  end
  
  def current_tenant_schema
    # Assuming you have apartment/acts_as_tenant setup
    Apartment::Tenant.current || 'public'
  end
  
  def build_context
    {
      tenant_schema: current_tenant_schema,
      user_email: current_user.email,
      has_prd: @conversation.prd_documents.completed.any?,
      current_theme: @conversation.latest_theme&.theme_config
    }
  end
  
  def extract_latest_requirements
    latest_prd = @conversation.prd_documents.completed.order(created_at: :desc).first
    latest_prd&.parsed_requirements || {}
  end
  
  def format_requirements(requirements)
    output = []
    
    requirements.each do |category, details|
      output << "**#{category.to_s.titleize}:**"
      if details.is_a?(Hash)
        details.each do |key, value|
          output << "  - #{key.to_s.titleize}: #{value}"
        end
      else
        output << "  #{details}"
      end
      output << ""
    end
    
    output.join("\n")
  end
  
  def authenticate_user!
    # Add your authentication logic here
    # This should check if user is logged in
  end
end
