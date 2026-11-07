"""Conversation API endpoints for chat-based theme customization."""

from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Query
from pydantic import BaseModel, Field
from typing import Optional
import logging
import io
from docx import Document
from PyPDF2 import PdfReader

from app.schemas import (
    ConversationStartRequest,
    ConversationStartResponse,
    ConversationMessageRequest,
    ConversationMessageResponse,
    PRDUploadResponse,
    ErrorResponse
)
from app.services.mock_llm import get_mock_llm
from app.services.claude_llm import get_llm_service, get_claude_llm
from app.services import site_importer
from app.services import screenshot_design
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post(
    "/conversations/start",
    response_model=ConversationStartResponse,
    summary="Start a new conversation",
    description="Initiates a new conversation session for theme customization"
)
async def start_conversation(
    request: ConversationStartRequest,
    use_real_llm: Optional[bool] = Query(None, description="Use real LLM (Claude) instead of Mock LLM")
):
    """
    Start a new conversation with the AI theme assistant.
    
    This endpoint creates a new conversation session and returns a conversation ID
    that should be used in all subsequent messages.
    """
    try:
        # Determine LLM mode: use query param if provided, else use config
        llm_mode = use_real_llm if use_real_llm is not None else settings.use_real_llm
        logger.info(f"Starting conversation for user {request.user_id}, tenant {request.tenant_id} (LLM: {'Real' if llm_mode else 'Mock'})")
        
        llm_service = get_llm_service(llm_mode)
        result = await llm_service.start_conversation(
            user_id=request.user_id,
            tenant_id=request.tenant_id
        )
        
        return ConversationStartResponse(**result)
    
    except Exception as e:
        logger.error(f"Error starting conversation: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "CONVERSATION_START_ERROR",
                    "message": "Failed to start conversation",
                    "details": str(e)
                }
            }
        )


@router.post(
    "/conversations/{conversation_id}/message",
    response_model=ConversationMessageResponse,
    summary="Send a message in conversation",
    description="Send a user message and receive AI response with extracted information"
)
async def send_message(
    conversation_id: str,
    request: ConversationMessageRequest,
    use_real_llm: Optional[bool] = Query(None, description="Use real LLM (Claude) instead of Mock LLM")
):
    """
    Send a message in an active conversation.
    
    The AI will:
    - Analyze the message for store information
    - Extract relevant details (store type, style preferences, etc.)
    - Provide contextual responses and suggestions
    - Indicate when enough information is gathered for theme generation
    """
    try:
        # Determine LLM mode: use query param if provided, else use config
        llm_mode = use_real_llm if use_real_llm is not None else settings.use_real_llm
        logger.info(f"Processing message for conversation {conversation_id} (LLM: {'Real' if llm_mode else 'Mock'})")
        
        llm_service = get_llm_service(llm_mode)
        result = await llm_service.send_message(
            conversation_id=conversation_id,
            message=request.message,
            context=request.context
        )
        
        return ConversationMessageResponse(**result)
    
    except ValueError as e:
        logger.warning(f"Invalid conversation ID: {conversation_id}")
        raise HTTPException(
            status_code=404,
            detail={
                "error": {
                    "code": "CONVERSATION_NOT_FOUND",
                    "message": "Conversation not found",
                    "details": str(e)
                }
            }
        )
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "MESSAGE_PROCESSING_ERROR",
                    "message": "Failed to process message",
                    "details": str(e)
                }
            }
        )


@router.post(
    "/conversations/{conversation_id}/upload-prd",
    response_model=PRDUploadResponse,
    summary="Upload PRD document",
    description="Upload a Product Requirements Document (PDF, DOCX, TXT, MD) for analysis"
)
async def upload_prd(
    conversation_id: str,
    file: UploadFile = File(..., description="PRD document file"),
    use_real_llm: Optional[bool] = Query(None, description="Use Real LLM (Claude) instead of Mock")
):
    """
    Upload and process a PRD document.
    
    Supported formats: PDF, DOCX, TXT, MD
    Maximum file size: 10 MB
    
    The AI will:
    - Extract text content from the document
    - Analyze requirements and brand information
    - Extract colors, style preferences, and other relevant details
    - Prepare for theme generation
    """
    try:
        # Determine which LLM to use
        should_use_real_llm = use_real_llm if use_real_llm is not None else settings.use_real_llm
        llm_mode = "Real LLM (Claude)" if should_use_real_llm else "Mock LLM"
        logger.info(f"Processing PRD with {llm_mode}")
        
        # Validate file type
        file_ext = file.filename.split('.')[-1].lower() if file.filename else ''
        if file_ext not in settings.allowed_file_types:
            raise HTTPException(
                status_code=400,
                detail={
                    "error": {
                        "code": "INVALID_FILE_TYPE",
                        "message": f"File type '{file_ext}' not supported",
                        "details": {
                            "allowed_types": settings.allowed_file_types
                        }
                    }
                }
            )
        
        # Read file content
        content = await file.read()
        
        # Check file size
        file_size_mb = len(content) / (1024 * 1024)
        if file_size_mb > settings.max_prd_file_size_mb:
            raise HTTPException(
                status_code=400,
                detail={
                    "error": {
                        "code": "FILE_TOO_LARGE",
                        "message": f"File size {file_size_mb:.2f}MB exceeds limit of {settings.max_prd_file_size_mb}MB"
                    }
                }
            )
        
        # Process document
        logger.info(f"Processing PRD document '{file.filename}' for conversation {conversation_id}")
        
        # Extract text based on file type
        filename_lower = file.filename.lower()
        try:
            if filename_lower.endswith('.docx'):
                # Parse DOCX
                doc = Document(io.BytesIO(content))
                text_content = '\n'.join([paragraph.text for paragraph in doc.paragraphs])
                logger.info(f"Extracted {len(text_content)} characters from DOCX")
            elif filename_lower.endswith('.pdf'):
                # Parse PDF
                pdf = PdfReader(io.BytesIO(content))
                text_content = '\n'.join([page.extract_text() for page in pdf.pages])
                logger.info(f"Extracted {len(text_content)} characters from PDF")
            elif filename_lower.endswith(('.txt', '.md')):
                # Plain text
                text_content = content.decode('utf-8', errors='ignore')
                logger.info(f"Extracted {len(text_content)} characters from text file")
            else:
                # Fallback: try UTF-8 decode
                text_content = content.decode('utf-8', errors='ignore')
                logger.warning(f"Unknown file type '{filename_lower}', attempted UTF-8 decode")
        except Exception as e:
            logger.error(f"Failed to parse document: {e}")
            raise HTTPException(
                status_code=400,
                detail={
                    "error": {
                        "code": "DOCUMENT_PARSE_ERROR",
                        "message": f"Failed to parse document: {str(e)}"
                    }
                }
            )
        
        # Use the appropriate LLM service based on mode
        llm_service = get_llm_service(use_real_llm=should_use_real_llm)
        result = await llm_service.process_prd(
            conversation_id=conversation_id,
            file_content=text_content,
            file_name=file.filename
        )
        
        return PRDUploadResponse(**result)
    
    except HTTPException:
        raise
    except ValueError as e:
        logger.warning(f"Invalid conversation ID: {conversation_id}")
        raise HTTPException(
            status_code=404,
            detail={
                "error": {
                    "code": "CONVERSATION_NOT_FOUND",
                    "message": "Conversation not found"
                }
            }
        )
    except Exception as e:
        logger.error(f"Error processing PRD: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "PRD_PROCESSING_ERROR",
                    "message": "Failed to process PRD document",
                    "details": str(e)
                }
            }
        )


class SampleProductsRequest(BaseModel):
    store_type: str = Field(..., min_length=1, max_length=200)
    store_name: Optional[str] = "My Store"
    count: int = Field(8, ge=1, le=20)
    currency: str = "USD"


@router.post(
    "/sample-products",
    summary="Generate sample products",
    description="Generate realistic sample products (with photos) for a new store of the given type"
)
async def sample_products(request: SampleProductsRequest):
    """Generate sample products for a new store so it doesn't start empty."""
    try:
        logger.info(f"Generating {request.count} sample products for '{request.store_type}'")
        llm = get_claude_llm()
        products = await llm.generate_sample_products(
            store_type=request.store_type,
            store_name=request.store_name or "My Store",
            count=request.count,
            currency=request.currency
        )
        return {"products": products}
    except Exception as e:
        logger.error(f"Error generating sample products: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "SAMPLE_PRODUCTS_ERROR",
                    "message": "Failed to generate sample products",
                    "details": str(e)
                }
            }
        )


class PagePlanFamily(BaseModel):
    """A style family the shop can use."""
    key: str
    name: str = ""
    fits: str = ""


class PagePlanRequest(BaseModel):
    """Request body for the home page plan."""
    store_name: str = Field(..., min_length=1, max_length=200)
    description: str = Field("", max_length=2000)
    currency: str = "USD"
    families: list[PagePlanFamily] = Field(default_factory=list)


@router.post(
    "/page-plan",
    summary="Write the home page plan",
    description="Choose a style family and write the words and photo searches for a store's home page sections, with one photo per photo section"
)
async def page_plan(request: PagePlanRequest):
    """The AI writes the words for the designer-made sections. It never writes CSS."""
    try:
        logger.info(f"Writing page plan for '{request.store_name}'")
        llm = get_claude_llm()
        result = await llm.generate_page_plan(
            store_name=request.store_name,
            description=request.description or request.store_name,
            currency=request.currency,
            families=[family.model_dump() for family in request.families]
        )
        return result
    except Exception as e:
        logger.error(f"Error writing page plan: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "PAGE_PLAN_ERROR",
                    "message": "Failed to write the page plan",
                    "details": str(e)
                }
            }
        )


class SiteImportRequest(BaseModel):
    """Request body for moving an existing store to Tellora."""
    url: str = Field(..., min_length=4, max_length=500)
    store_name: str = Field("", max_length=200)
    currency: str = "USD"
    families: list[PagePlanFamily] = Field(default_factory=list)


@router.post(
    "/site-import",
    summary="Read an existing store and plan its new home page",
    description="Reads the brand of a store the owner is moving to Tellora (logo, colours, fonts, words, photos) "
                "and writes the home page plan with the store's own words. Never copies theme code."
)
async def site_import(request: SiteImportRequest):
    """Read the store the owner is moving from and write its new home page plan."""
    try:
        site = await site_importer.read_site(request.url)
    except site_importer.ImportError_ as e:
        logger.info(f"Site import refused for {request.url}: {e}")
        raise HTTPException(status_code=422, detail={"error": {"code": "SITE_IMPORT_FAILED", "message": str(e)}})
    except Exception as e:
        logger.error(f"Site import crashed for {request.url}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail={"error": {"code": "SITE_IMPORT_ERROR", "message": "We could not read the store"}})

    store_name = request.store_name or site["brand"]["site_name"] or "our shop"
    summary = site_importer.summary_for_plan(site, store_name)

    try:
        llm = get_claude_llm()
        result = await llm.generate_page_plan(
            store_name=store_name,
            description=summary,
            currency=request.currency,
            families=[family.model_dump() for family in request.families]
        )
    except Exception as e:
        logger.error(f"Page plan for imported store failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail={"error": {"code": "PAGE_PLAN_ERROR", "message": "We could not write the new home page"}})

    # The store's own photos come first; stock photos only fill the gaps
    images = dict(result.get("images") or {})
    own = [u for u in site["photos"] if u.startswith("https://")]
    for slot, url in zip(("hero", "story", "banner"), own):
        images[slot] = {"url": url, "user": site["brand"]["site_name"], "page_url": site["brand"]["source_url"], "query": "own photo"}

    description = site["brand"]["description"] or " ".join(site["words"]["headings"][:3])
    return {
        "brand": site["brand"],
        "plan": result.get("plan") or {},
        "images": images,
        "description": (description or store_name)[:480],
    }


SCREENSHOT_MAX_BYTES = 20 * 1024 * 1024
SCREENSHOT_TYPES = ("image/png", "image/jpeg", "image/webp")


async def _screenshot_bytes(upload: Optional[UploadFile], label: str) -> Optional[bytes]:
    if upload is None:
        return None
    data = await upload.read()
    if not data:
        return None
    if len(data) > SCREENSHOT_MAX_BYTES:
        raise HTTPException(status_code=422, detail={"error": {"code": "SCREENSHOT_TOO_LARGE", "message": f"The {label} screenshot is larger than 20 MB"}})
    if not (data[:8] == b"\x89PNG\r\n\x1a\n" or data[:3] == b"\xff\xd8\xff" or (data[:4] == b"RIFF" and data[8:12] == b"WEBP")):
        raise HTTPException(status_code=422, detail={"error": {"code": "SCREENSHOT_TYPE", "message": f"The {label} screenshot must be a PNG, JPG or WEBP image"}})
    return data


@router.post(
    "/screenshot-design",
    summary="Rebuild a store home page from screenshots",
    description="Takes a full-page desktop screenshot (and optionally a mobile one) of a store's home page and returns "
                "HTML/CSS that matches it, checked by rendering and comparing in a real browser."
)
async def screenshot_design_endpoint(
    desktop: UploadFile = File(..., description="Full-page desktop screenshot of the home page"),
    mobile: Optional[UploadFile] = File(None, description="Full-page phone screenshot of the home page (optional)"),
    store_name: str = Form("", max_length=200),
):
    desktop_bytes = await _screenshot_bytes(desktop, "desktop")
    if not desktop_bytes:
        raise HTTPException(status_code=422, detail={"error": {"code": "SCREENSHOT_MISSING", "message": "The desktop screenshot is missing"}})
    mobile_bytes = await _screenshot_bytes(mobile, "mobile")

    try:
        return await screenshot_design.build_design(desktop_bytes, mobile_bytes, store_name or "the store")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Screenshot design failed for {store_name}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail={"error": {"code": "SCREENSHOT_DESIGN_ERROR", "message": "We could not rebuild the design from the screenshot"}})