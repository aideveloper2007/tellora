from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # LLM Configuration
    llm_provider: str = "openai"  # openai, anthropic, or ollama
    openai_api_key: Optional[str] = None
    anthropic_api_key: Optional[str] = None
    openai_model: str = "gpt-4o"
    anthropic_model: str = "claude-3-5-sonnet-20241022"
    
    # Service Configuration
    service_host: str = "0.0.0.0"
    service_port: int = 8000
    debug: bool = True
    
    # Rails Integration
    rails_api_url: str = "http://localhost:3000"
    rails_api_token: Optional[str] = None
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
