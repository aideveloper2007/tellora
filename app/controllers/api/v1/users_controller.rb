# app/controllers/api/v1/users_controller.rb
class Api::V1::UsersController < ApplicationController
  protect_from_forgery with: :null_session
  before_action :authenticate_api_key
  
  def create
    Rails.logger.info "=== User Creation Request ==="
    Rails.logger.info "Params: #{user_params.inspect}"
    
    begin
      user = User.new(user_params)
      
      if user.save
        Rails.logger.info "User created successfully: #{user.email}"
        
        render json: {
          success: true,
          message: "User created successfully",
          data: {
            id: user.id,
            email: user.email,
            name: user.name,
            surname: user.surname,
            country: user.country,
            created_at: user.created_at
          }
        }, status: :created
      else
        Rails.logger.error "User validation failed: #{user.errors.full_messages}"
        
        render json: {
          success: false,
          message: "User validation failed",
          errors: user.errors.full_messages
        }, status: :unprocessable_entity
      end
      
    rescue => e
      Rails.logger.error "User creation error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        message: "Internal server error",
        errors: [e.message]
      }, status: :internal_server_error
    end
  end
  
  private
  
  def authenticate_api_key
    api_key = request.headers['Authorization']&.gsub('Bearer ', '')
    
    unless api_key == Rails.application.credentials.dig(:lms_api_key)
      render json: { 
        success: false,
        message: 'Unauthorized - Invalid API Key' 
      }, status: :unauthorized
    end
  end
  
  def user_params
    params.permit(:email, :password, :name, :surname, :country)
      .tap do |permitted|
        # Clean up email
        permitted[:email] = permitted[:email]&.downcase&.strip
        
        # Set default country if not provided
        permitted[:country] = 'US' if permitted[:country].blank?
      end
  end
end