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