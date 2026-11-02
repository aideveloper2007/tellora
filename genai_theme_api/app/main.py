"""FastAPI application entry point."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import logging

from app.config import settings
from app.api.v1 import conversations, themes, images, admin
from app.services.pixabay_service import PixabayService
from app.services.mock_llm import initialize_mock_llm
from app.services.claude_llm import initialize_claude_llm
from app.services.pgvector_store import initialize_pgvector_store, close_pgvector_store
from app.services.context_manager import initialize_context_manager
from app.orchestrators.theme_orchestrator import initialize_theme_orchestrator

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize Pixabay service
pixabay_service = None
if settings.pixabay_api_key:
    pixabay_service = PixabayService(api_key=settings.pixabay_api_key)
    logger.info("Pixabay service initialized")
else:
    logger.warning("Pixabay API key not found - images will be placeholders")

# Initialize LLM service based on feature flag
if settings.use_real_llm and settings.llm_provider == "claude":
    try:
        initialize_claude_llm(pixabay_service=pixabay_service)
        logger.info("✅ Claude AI (Real LLM) initialized successfully")
    except Exception as e:
        logger.error(f"❌ Failed to initialize Claude LLM: {str(e)}")
        logger.warning("🔄 Falling back to mock LLM")
        initialize_mock_llm(pixabay_service=pixabay_service)
else:
    initialize_mock_llm(pixabay_service=pixabay_service)
    logger.info("🧪 Mock LLM initialized (use_real_llm=False or llm_provider=mock)")

# Create FastAPI app
app = FastAPI(
    title="GenAI Theme API",
    description="AI-powered theme generation service for e-commerce stores",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=settings.cors_allow_credentials,
    allow_methods=settings.cors_allow_methods,
    allow_headers=settings.cors_allow_headers,
)


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup."""
    logger.info("🚀 Starting GenAI Theme API...")
    
    # DISABLED: PgVectorStore (sentence-transformers) - not used in current implementation
    # Uncomment if you need semantic search features
    # try:
    #     await initialize_pgvector_store(
    #         database_url=settings.database_url,
    #         openai_api_key=settings.openai_api_key
    #     )
    #     logger.info("✅ PgVectorStore initialized")
    # except Exception as e:
    #     logger.error(f"❌ Failed to initialize PgVectorStore: {str(e)}")
    
    # Initialize ContextManager for token management
    try:
        initialize_context_manager()
        logger.info("✅ ContextManager initialized")
    except Exception as e:
        logger.error(f"❌ Failed to initialize ContextManager: {str(e)}")
    
    # Initialize ThemeOrchestrator for generation workflow
    try:
        initialize_theme_orchestrator(
            max_attempts=3,
            quality_threshold=70,
            max_cost_usd=0.50
        )
        logger.info("✅ ThemeOrchestrator initialized")
    except Exception as e:
        logger.error(f"❌ Failed to initialize ThemeOrchestrator: {str(e)}")
    
    logger.info("🎉 All services initialized successfully")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown."""
    logger.info("🛑 Shutting down GenAI Theme API...")
    
    # DISABLED: PgVectorStore cleanup (not initialized)
    # try:
    #     await close_pgvector_store()
    #     logger.info("✅ PgVectorStore closed")
    # except Exception as e:
    #     logger.error(f"❌ Failed to close PgVectorStore: {str(e)}")


@app.get("/")
async def root():
    """Root endpoint - health check."""
    llm_service = None
    try:
        from app.services.claude_llm import get_llm_service
        llm_service = get_llm_service()
    except:
        pass
    
    llm_type = "claude" if (llm_service and hasattr(llm_service, 'client')) else "mock"
    
    return {
        "service": "GenAI Theme API",
        "version": "1.0.0",
        "status": "healthy",
        "llm": {
            "provider": llm_type,
            "use_real_llm": settings.use_real_llm,
            "claude_available": bool(settings.claude_api_key)
        },
        "images": {
            "pixabay_available": bool(settings.pixabay_api_key)
        }
    }


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "environment": settings.environment
    }


# Include API routers
app.include_router(
    conversations.router,
    prefix="/api/v1",
    tags=["Conversations"]
)

app.include_router(
    themes.router,
    prefix="/api/v1",
    tags=["Themes"]
)

app.include_router(
    images.router,
    prefix="/api/v1",
    tags=["Images"]
)

app.include_router(
    admin.router,
    prefix="/api/v1",
    tags=["Admin"]
)


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler."""
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_SERVER_ERROR",
                "message": "An unexpected error occurred. Please try again later."
            }
        }
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug
    )
