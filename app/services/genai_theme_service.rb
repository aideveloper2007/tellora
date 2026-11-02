require 'httparty'

class GenaiThemeService
  include HTTParty
  base_uri ENV.fetch('GENAI_SERVICE_URL', 'http://localhost:8000')
  
  attr_reader :conversation_id
  
  def initialize(tenant_id:, user_id:)
    @tenant_id = tenant_id
    @user_id = user_id
    @conversation_id = nil
    @options = {
      headers: {
        'Content-Type' => 'application/json'
      },
      timeout: 120 # 2 minutes for LLM processing
    }
  end
  
  # === Conversation Management ===
  
  def start_conversation(use_real_llm: nil)
    # Build query params
    query_params = {}
    query_params[:use_real_llm] = use_real_llm unless use_real_llm.nil?
    query_string = query_params.empty? ? '' : '?' + URI.encode_www_form(query_params)
    
    response = self.class.post("/api/v1/conversations/start#{query_string}",
      body: {
        user_id: @user_id.to_s,
        tenant_id: @tenant_id.to_s
      }.to_json,
      **@options
    )
    
    result = handle_response(response)
    @conversation_id = result['conversation_id']
    result
  end
  
  def send_message(message:, context: {}, use_real_llm: nil)
    conversation_id = @conversation_id || raise(ArgumentError, 'No active conversation. Call start_conversation first.')
    
    # Build query params
    query_params = {}
    query_params[:use_real_llm] = use_real_llm unless use_real_llm.nil?
    query_string = query_params.empty? ? '' : '?' + URI.encode_www_form(query_params)
    
    response = self.class.post("/api/v1/conversations/#{conversation_id}/message#{query_string}",
      body: {
        message: message,
        context: context
      }.to_json,
      **@options
    )
    
    handle_response(response)
  end
  
  def upload_prd(file_path:, use_real_llm: nil)
    conversation_id = @conversation_id || raise(ArgumentError, 'No active conversation. Call start_conversation first.')
    
    # Build query params
    query_params = {}
    query_params[:use_real_llm] = use_real_llm unless use_real_llm.nil?
    query_string = query_params.empty? ? '' : '?' + URI.encode_www_form(query_params)
    
    response = self.class.post("/api/v1/conversations/#{conversation_id}/upload-prd#{query_string}",
      body: {
        file: File.new(file_path, 'rb')
      },
      headers: {}, # Don't set Content-Type for multipart
      timeout: 120
    )
    
    handle_response(response)
  end
  
  # === Theme Generation ===
  
  def generate_theme(store_type: 'general', template: nil, requirements: {}, use_real_llm: nil)
    # Use conversation_id if available, otherwise proceed without it
    body = {
      store_type: store_type,
      requirements: requirements,
      tenant_id: @tenant_id
    }
    
    body[:conversation_id] = @conversation_id if @conversation_id
    body[:template] = template if template
    body[:use_real_llm] = use_real_llm unless use_real_llm.nil?
    
    response = self.class.post('/api/v1/themes/generate',
      body: body.to_json,
      **@options
    )
    
    handle_response(response)
  end
  
  def get_theme_status(theme_id:)
    response = self.class.get("/api/v1/themes/#{theme_id}/status",
      **@options
    )
    
    handle_response(response)
  end
  
  def refine_theme(theme_id:, feedback:)
    response = self.class.post("/api/v1/themes/#{theme_id}/refine",
      body: {
        feedback: feedback
      }.to_json,
      **@options
    )
    
    handle_response(response)
  end
  
  def validate_theme(theme:)
    response = self.class.post('/api/v1/themes/validate',
      body: {
        theme: theme
      }.to_json,
      **@options
    )
    
    handle_response(response)
  end
  
  # === Images ===
  
  def fetch_images(theme_id:, category:, count: 6)
    response = self.class.get('/api/v1/images/fetch',
      query: {
        theme_id: theme_id,
        category: category,
        count: count
      },
      **@options
    )
    
    handle_response(response)
  end
  
  # === Health Check ===
  
  def health_check
    response = self.class.get('/health', **@options)
    handle_response(response)
  end
  
  private
  
  def handle_response(response)
    case response.code
    when 200..299
      JSON.parse(response.body)
    when 400..499
      error_body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        { 'detail' => response.body }
      end
      raise "Client error: #{response.code} - #{error_body['detail'] || response.body}"
    when 500..599
      raise "Server error: #{response.code} - #{response.body}"
    else
      raise "Unexpected response: #{response.code}"
    end
  rescue JSON::ParserError
    raise "Invalid JSON response: #{response.body}"
  end
end
