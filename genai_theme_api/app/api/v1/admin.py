"""Admin endpoints for feature flags and system monitoring."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, Any
import logging

from app.config import settings
from app.services.claude_llm import get_llm_service, initialize_claude_llm
from app.services.mock_llm import initialize_mock_llm
from app.services.pixabay_service import PixabayService

router = APIRouter(prefix="/admin", tags=["admin"])
logger = logging.getLogger(__name__)


class FeatureFlagUpdate(BaseModel):
    """Request model for updating feature flags."""
    use_real_llm: bool
    llm_provider: str = "claude"


class SystemStatus(BaseModel):
    """Response model for system status."""
    status: str
    llm_provider: str
    use_real_llm: bool
    claude_available: bool
    pixabay_available: bool
    environment: str


@router.get("/status", response_model=SystemStatus)
async def get_system_status():
    """
    Get current system status and feature flags.
    
    Returns:
        SystemStatus: Current system configuration
    """
    llm_service = get_llm_service()
    llm_type = "claude" if hasattr(llm_service, 'client') else "mock"
    
    return SystemStatus(
        status="operational",
        llm_provider=llm_type,
        use_real_llm=settings.use_real_llm,
        claude_available=bool(settings.claude_api_key),
        pixabay_available=bool(settings.pixabay_api_key),
        environment=settings.environment
    )


@router.post("/feature-flags/llm")
async def update_llm_feature_flag(flag_update: FeatureFlagUpdate):
    """
    Toggle LLM provider between Claude AI and Mock.
    
    This allows runtime switching without restarting the server.
    Useful for testing, debugging, or emergency fallback.
    
    Args:
        flag_update: Feature flag configuration
        
    Returns:
        Dict with updated status
    """
    try:
        # Update settings
        settings.use_real_llm = flag_update.use_real_llm
        settings.llm_provider = flag_update.llm_provider
        
        # Get Pixabay service if available
        pixabay_service = None
        if settings.pixabay_api_key:
            pixabay_service = PixabayService(api_key=settings.pixabay_api_key)
        
        # Reinitialize LLM service
        if flag_update.use_real_llm and flag_update.llm_provider == "claude":
            if not settings.claude_api_key:
                raise HTTPException(
                    status_code=400,
                    detail="Claude API key not configured. Cannot enable real LLM."
                )
            initialize_claude_llm(pixabay_service=pixabay_service)
            logger.info("✅ Switched to Claude AI (Real LLM)")
            message = "Switched to Claude AI successfully"
        else:
            initialize_mock_llm(pixabay_service=pixabay_service)
            logger.info("🧪 Switched to Mock LLM")
            message = "Switched to Mock LLM successfully"
        
        return {
            "status": "success",
            "message": message,
            "use_real_llm": flag_update.use_real_llm,
            "llm_provider": flag_update.llm_provider
        }
        
    except Exception as e:
        logger.error(f"Failed to update LLM feature flag: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to switch LLM provider: {str(e)}"
        )


@router.get("/health")
async def health_check():
    """
    Basic health check endpoint.
    
    Returns:
        Dict with health status
    """
    return {
        "status": "healthy",
        "service": "GenAI Theme API",
        "version": "1.0.0"
    }
