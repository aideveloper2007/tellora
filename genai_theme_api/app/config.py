"""Application configuration using Pydantic settings."""

from pydantic_settings import BaseSettings
from typing import List
from pydantic import field_validator


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""
    
    # API Configuration
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    debug: bool = True
    environment: str = "development"
    
    # CORS Settings
    cors_origins: List[str] = ["http://localhost:3000", "http://localhost:5000"]
    cors_allow_credentials: bool = True
    cors_allow_methods: List[str] = ["*"]
    cors_allow_headers: List[str] = ["*"]
    
    @field_validator('cors_origins', mode='before')
    @classmethod
    def parse_cors_origins(cls, v):
        """Parse comma-separated CORS origins."""
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(',')]
        return v
    
    @field_validator('cors_allow_methods', 'cors_allow_headers', mode='before')
    @classmethod
    def parse_cors_settings(cls, v):
        """Parse comma-separated CORS settings."""
        if isinstance(v, str):
            return [item.strip() for item in v.split(',')]
        return v
    
    # API Keys
    claude_api_key: str = ""
    openai_api_key: str = ""  # For embeddings
    unsplash_access_key: str = ""
    pixabay_api_key: str = ""
    
    # Feature Flags
    # LLM Provider Selection
    use_real_llm: bool = True  # True = Claude AI, False = Mock LLM
    llm_provider: str = "claude"  # Options: "claude", "mock"
    
    # Legacy Mock Mode (for backward compatibility)
    mock_llm_mode: bool = False  # Deprecated: Use use_real_llm instead
    mock_image_mode: bool = False
    
    # Rate Limiting
    rate_limit_per_minute: int = 60
    rate_limit_per_hour: int = 1000
    
    # Database (optional)
    database_url: str = "postgresql://amars:password@localhost:5432/saasapplication_development"
    
    # Logging
    log_level: str = "INFO"
    log_file: str = "logs/api.log"
    
    # Validation
    max_prd_file_size_mb: int = 10
    allowed_file_types: List[str] = ["pdf", "docx", "txt", "md"]
    template_match_threshold: float = 0.85
    quality_threshold: float = 0.8
    max_refinement_retries: int = 3
    
    @field_validator('allowed_file_types', mode='before')
    @classmethod
    def parse_allowed_file_types(cls, v):
        """Parse comma-separated allowed file types."""
        if isinstance(v, str):
            return [ftype.strip() for ftype in v.split(',')]
        return v
    
    # Theme Generation
    default_template: str = "template_modern_002"
    theme_generation_timeout_seconds: int = 30
    
    class Config:
        env_file = ".env"
        case_sensitive = False


# Global settings instance
settings = Settings()
