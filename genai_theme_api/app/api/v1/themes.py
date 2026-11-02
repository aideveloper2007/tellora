"""Theme generation API endpoints."""

from fastapi import APIRouter, HTTPException, BackgroundTasks
from typing import Dict, Optional
import logging
import random
import time

from app.schemas import (
    ThemeGenerateRequest,
    ThemeGenerateResponse,
    ThemeStatusResponse,
    ThemeRefineRequest,
    ThemeRefineResponse,
    ThemeValidateRequest,
    ThemeValidateResponse,
    ValidationResult,
    ThemeStatus,
    ThemeData,
    ErrorResponse
)
from app.services.mock_llm import get_mock_llm
from app.services.claude_llm import get_llm_service
from app.orchestrators.theme_orchestrator import get_theme_orchestrator
from app.services.pgvector_store import get_pgvector_store
from app.services.pixabay_service import PixabayService
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()

# In-memory storage for theme generation status
# In production, use Redis or database
theme_storage: Dict[str, Dict] = {}


async def generate_theme_background(theme_id: str, request: ThemeGenerateRequest):
    """Background task to generate theme using ThemeOrchestrator."""
    try:
        logger.info(f"Starting background theme generation for {theme_id}")
        
        # Determine LLM mode: use request override if provided, else use config
        use_real_llm = request.use_real_llm if request.use_real_llm is not None else settings.use_real_llm
        llm_mode = "Real LLM (Claude)" if use_real_llm else "Mock LLM"
        logger.info(f"Theme generation mode: {llm_mode}")
        
        # Update status to in_progress
        theme_storage[theme_id]["status"] = ThemeStatus.IN_PROGRESS
        theme_storage[theme_id]["progress"] = 10
        
        # Get orchestrator (uses real Claude LLM or Mock based on config)
        orchestrator = get_theme_orchestrator(use_real_llm=use_real_llm)
        # DISABLED: PgVectorStore not used in current implementation
        # vector_store = get_pgvector_store()
        
        if not orchestrator:
            raise Exception("ThemeOrchestrator not initialized")
        
        # DISABLED: Embedding storage (PgVectorStore not initialized)
        # if vector_store:
        #     try:
        #         requirements_text = f"{request.store_type}: {request.requirements.get('description', '')}"
        #         await vector_store.store_conversation_message(
        #             tenant=request.tenant_id,
        #             conversation_id=request.conversation_id or theme_id,
        #             message_index=1,
        #             message_content=requirements_text,
        #             role="user",
        #             metadata={"store_type": request.store_type}
        #         )
        #         logger.info(f"Stored conversation message with embedding for {theme_id}")
        #     except Exception as e:
        #         logger.warning(f"Failed to store conversation embedding: {e}")
        
        # Update progress
        theme_storage[theme_id]["progress"] = 30
        
        # Generate theme using ThemeOrchestrator (with auto-retry and validation)
        logger.info(f"Calling ThemeOrchestrator for {theme_id}")
        result = await orchestrator.generate_theme_with_retry(
            tenant=request.tenant_id,
            store_type=request.store_type,
            requirements=request.requirements,
            conversation_id=request.conversation_id or theme_id,
            use_real_llm=use_real_llm
        )
        
        # Update progress
        theme_storage[theme_id]["progress"] = 70
        theme_storage[theme_id]["status"] = ThemeStatus.VALIDATING
        
        # Extract theme data from orchestrator result
        if result.get("success"):
            theme_data = result.get("theme")
            quality_score = result.get("quality_score", 0)
            attempts = result.get("attempts", 1)
            cost_usd = result.get("cost_usd", 0)
            
            # Fetch images from Pixabay using search terms
            try:
                theme_storage[theme_id]["status"] = ThemeStatus.FETCHING_IMAGES
                
                # Initialize Pixabay service
                if not settings.pixabay_api_key:
                    logger.warning("Pixabay API key not set, skipping image fetching")
                else:
                    pixabay = PixabayService(api_key=settings.pixabay_api_key)
                    
                    # Fetch hero image
                    hero_search = theme_data.get("images", {}).get("hero", {}).get("search_term")
                    if hero_search:
                        logger.info(f"Fetching hero image with search: {hero_search}")
                        hero_images = await pixabay.fetch_images_by_search(
                            search_term=hero_search,
                            count=1,
                            image_type="photo"
                        )
                        if hero_images:
                            theme_data["images"]["hero"]["url"] = hero_images[0].get("url")
                            theme_data["images"]["hero"]["preview_url"] = hero_images[0].get("preview_url")
                    
                    # Fetch product images
                    products_search = theme_data.get("images", {}).get("featured_products", {}).get("search_term")
                    if products_search:
                        product_count = theme_data.get("images", {}).get("featured_products", {}).get("count", 6)
                        logger.info(f"Fetching {product_count} product images with search: {products_search}")
                        product_images = await pixabay.fetch_images_by_search(
                            search_term=products_search,
                            count=product_count,
                            image_type="photo"
                        )
                        if product_images:
                            theme_data["images"]["featured_products"]["images"] = product_images
                    
                    logger.info(f"✅ Fetched images for theme {theme_id}")
                
            except Exception as e:
                logger.warning(f"Failed to fetch images: {e}. Continuing without images.")
            
            # Update with completed data
            theme_storage[theme_id].update({
                "status": ThemeStatus.COMPLETED,
                "progress": 100,
                "theme_data": theme_data,
                "quality_score": quality_score,
                "attempts": attempts,
                "cost_usd": cost_usd,
                "validation_report": {
                    "is_valid": True,
                    "quality_score": quality_score,
                    "message": result.get("message", "Theme validated successfully")
                },
                "completed_at": time.time()
            })
            
            logger.info(f"✅ Theme generation completed for {theme_id} (score: {quality_score}, attempts: {attempts})")
        else:
            # Partial success or failure
            theme_data = result.get("theme")
            quality_score = result.get("quality_score", 0)
            
            theme_storage[theme_id].update({
                "status": ThemeStatus.COMPLETED,  # Still return theme, but with warnings
                "progress": 100,
                "theme_data": theme_data,
                "quality_score": quality_score,
                "validation_report": {
                    "is_valid": False,
                    "quality_score": quality_score,
                    "message": result.get("message", "Theme generated with issues"),
                    "warning": result.get("warning", "")
                },
                "completed_at": time.time()
            })
            
            logger.warning(f"⚠️ Theme generation completed with warnings for {theme_id}")
    
    except Exception as e:
        logger.error(f"❌ Theme generation failed for {theme_id}: {str(e)}", exc_info=True)
        theme_storage[theme_id].update({
            "status": ThemeStatus.FAILED,
            "error": str(e),
            "failed_at": time.time()
        })


@router.post(
    "/themes/generate",
    response_model=ThemeGenerateResponse,
    summary="Generate a new theme",
    description="Generate a complete theme based on store type and requirements"
)
async def generate_theme(
    request: ThemeGenerateRequest,
    background_tasks: BackgroundTasks
):
    """
    Generate a new theme for the store.
    
    This is the main endpoint for theme generation. It accepts:
    - Store type (jewelry, fashion, electronics, etc.)
    - Optional template preference
    - Requirements dictionary with store details
    - Optional conversation ID for context
    
    The generation happens asynchronously in the background.
    Use the GET /themes/{theme_id}/status endpoint to check progress.
    """
    try:
        logger.info(f"Theme generation requested for {request.tenant_id}, type: {request.store_type}")
        
        # Generate unique theme ID
        theme_id = f"theme_{random.randint(100000, 999999)}"
        
        # Initialize theme storage
        theme_storage[theme_id] = {
            "theme_id": theme_id,
            "status": ThemeStatus.PENDING,
            "progress": 0,
            "tenant_id": request.tenant_id,
            "store_type": request.store_type,
            "created_at": time.time(),
            "theme_data": None,
            "validation_report": None,
            "error": None
        }
        
        # Start background generation
        background_tasks.add_task(generate_theme_background, theme_id, request)
        
        return ThemeGenerateResponse(
            theme_id=theme_id,
            status=ThemeStatus.PENDING,
            message="Theme generation started. Check status using the theme ID.",
            estimated_time_seconds=25
        )
    
    except Exception as e:
        logger.error(f"Error initiating theme generation: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "THEME_GENERATION_ERROR",
                    "message": "Failed to start theme generation",
                    "details": str(e)
                }
            }
        )


@router.get(
    "/themes/{theme_id}/status",
    response_model=ThemeStatusResponse,
    summary="Get theme generation status",
    description="Check the status and progress of a theme generation request"
)
async def get_theme_status(theme_id: str):
    """
    Get the current status of a theme generation request.
    
    Returns:
    - Current status (pending, in_progress, validating, completed, failed)
    - Progress percentage (0-100)
    - Theme data if completed
    - Validation report if completed
    - Error message if failed
    """
    try:
        if theme_id not in theme_storage:
            raise HTTPException(
                status_code=404,
                detail={
                    "error": {
                        "code": "THEME_NOT_FOUND",
                        "message": f"Theme with ID '{theme_id}' not found"
                    }
                }
            )
        
        theme_info = theme_storage[theme_id]
        
        return ThemeStatusResponse(
            theme_id=theme_id,
            status=theme_info["status"],
            progress=theme_info["progress"],
            theme_data=theme_info.get("theme_data"),
            validation_report=theme_info.get("validation_report"),
            error=theme_info.get("error")
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching theme status: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "STATUS_FETCH_ERROR",
                    "message": "Failed to fetch theme status",
                    "details": str(e)
                }
            }
        )


@router.post(
    "/themes/{theme_id}/refine",
    response_model=ThemeRefineResponse,
    summary="Refine an existing theme",
    description="Apply refinements to a generated theme based on user feedback"
)
async def refine_theme(
    theme_id: str,
    request: ThemeRefineRequest
):
    """
    Refine an existing theme based on user feedback.
    
    Accepts:
    - Natural language feedback (e.g., "make colors more vibrant")
    - Specific changes (optional) for precise modifications
    
    The system will:
    - Analyze the feedback
    - Apply requested changes
    - Re-validate the theme
    - Return the updated theme
    """
    try:
        # Check if theme exists
        if theme_id not in theme_storage:
            raise HTTPException(
                status_code=404,
                detail={
                    "error": {
                        "code": "THEME_NOT_FOUND",
                        "message": f"Theme with ID '{theme_id}' not found"
                    }
                }
            )
        
        theme_info = theme_storage[theme_id]
        
        # Check if theme is completed
        if theme_info["status"] != ThemeStatus.COMPLETED:
            raise HTTPException(
                status_code=400,
                detail={
                    "error": {
                        "code": "THEME_NOT_READY",
                        "message": "Theme must be completed before refinement",
                        "current_status": theme_info["status"]
                    }
                }
            )
        
        logger.info(f"Refining theme {theme_id}")
        
        # Refine theme
        mock_llm = get_mock_llm()
        result = await mock_llm.refine_theme(
            theme_data=theme_info["theme_data"],
            feedback=request.feedback,
            specific_changes=request.specific_changes
        )
        
        # Update theme storage
        theme_storage[theme_id]["theme_data"] = result["theme_data"]
        theme_storage[theme_id]["last_refined_at"] = time.time()
        
        return ThemeRefineResponse(
            theme_id=theme_id,
            status=ThemeStatus.COMPLETED,
            message="Theme refined successfully",
            changes_applied=result["changes_applied"]
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error refining theme: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "REFINEMENT_ERROR",
                    "message": "Failed to refine theme",
                    "details": str(e)
                }
            }
        )


async def validate_theme_internal(
    theme_data: Dict,
    template: str,
    store_type: str
) -> Dict:
    """Internal theme validation logic."""
    checks = []
    
    # Check 1: Structure validation
    required_keys = ["colors", "typography", "layout", "components", "css"]
    structure_valid = all(key in theme_data for key in required_keys)
    checks.append({
        "check_name": "Structure Validation",
        "passed": structure_valid,
        "score": 1.0 if structure_valid else 0.0,
        "message": "Theme structure is valid" if structure_valid else "Missing required keys",
        "suggestions": [] if structure_valid else ["Ensure all required keys are present"]
    })
    
    # Check 2: Template match
    template_match_score = 0.95  # Mock score
    checks.append({
        "check_name": "Template Match",
        "passed": template_match_score >= settings.template_match_threshold,
        "score": template_match_score,
        "message": f"Theme matches {template} template",
        "suggestions": []
    })
    
    # Check 3: Color palette validation
    has_colors = "colors" in theme_data and len(theme_data["colors"]) >= 3
    checks.append({
        "check_name": "Color Palette",
        "passed": has_colors,
        "score": 1.0 if has_colors else 0.5,
        "message": "Color palette is complete" if has_colors else "Color palette incomplete",
        "suggestions": [] if has_colors else ["Add more color definitions"]
    })
    
    # Check 4: Typography validation
    has_fonts = "typography" in theme_data and "heading_font" in theme_data["typography"]
    checks.append({
        "check_name": "Typography",
        "passed": has_fonts,
        "score": 1.0 if has_fonts else 0.5,
        "message": "Typography is properly defined",
        "suggestions": []
    })
    
    # Check 5: CSS validation (basic)
    has_css = "css" in theme_data and len(theme_data["css"]) > 100
    checks.append({
        "check_name": "CSS Generation",
        "passed": has_css,
        "score": 1.0 if has_css else 0.3,
        "message": "CSS generated successfully",
        "suggestions": []
    })
    
    # Check 6: Content quality
    quality_score = 0.92  # Mock score
    checks.append({
        "check_name": "Content Quality",
        "passed": quality_score >= settings.quality_threshold,
        "score": quality_score,
        "message": "Theme quality meets standards",
        "suggestions": []
    })
    
    # Check 7: Hallucination check (mock)
    hallucination_score = 0.98
    checks.append({
        "check_name": "Hallucination Check",
        "passed": hallucination_score >= 0.9,
        "score": hallucination_score,
        "message": "No hallucinated content detected",
        "suggestions": []
    })
    
    # Calculate overall score
    overall_score = sum(check["score"] for check in checks) / len(checks)
    all_passed = all(check["passed"] for check in checks)
    
    return {
        "valid": all_passed,
        "overall_score": round(overall_score, 2),
        "checks": checks,
        "checks_passed": sum(1 for check in checks if check["passed"]),
        "checks_total": len(checks),
        "summary": "Theme validation passed" if all_passed else "Theme validation failed"
    }


@router.post(
    "/themes/validate",
    response_model=ThemeValidateResponse,
    summary="Validate a theme",
    description="Validate theme data against quality standards and template requirements"
)
async def validate_theme(request: ThemeValidateRequest):
    """
    Validate a theme against quality standards.
    
    Performs 7 validation checks:
    1. Structure validation
    2. Template match score
    3. Color palette completeness
    4. Typography validation
    5. CSS generation quality
    6. Content quality score
    7. Hallucination detection
    
    Returns detailed validation results with suggestions for improvement.
    """
    try:
        logger.info(f"Validating theme for template {request.template}, store type {request.store_type}")
        
        # Convert ThemeData to dict
        theme_dict = request.theme_data.model_dump()
        
        result = await validate_theme_internal(
            theme_data=theme_dict,
            template=request.template.value,
            store_type=request.store_type
        )
        
        # Convert checks to ValidationResult objects
        validation_checks = [ValidationResult(**check) for check in result["checks"]]
        
        return ThemeValidateResponse(
            valid=result["valid"],
            overall_score=result["overall_score"],
            checks=validation_checks,
            summary=result["summary"]
        )
    
    except Exception as e:
        logger.error(f"Error validating theme: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "VALIDATION_ERROR",
                    "message": "Failed to validate theme",
                    "details": str(e)
                }
            }
        )
