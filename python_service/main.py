from fastapi import FastAPI, UploadFile, File, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
import uvicorn
import os
from dotenv import load_dotenv

from services.llm_service import LLMService
from services.document_parser import DocumentParser
from services.theme_generator import ThemeGenerator
from config import settings

load_dotenv()

app = FastAPI(
    title="GenAI Theme Service",
    description="AI-powered theme generation service for ecommerce stores",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:3001"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize services
llm_service = LLMService()
document_parser = DocumentParser()
theme_generator = ThemeGenerator(llm_service)


# Request/Response Models
class ChatRequest(BaseModel):
    conversation_id: str
    message: str
    tenant_schema: str
    context: Optional[Dict[str, Any]] = None


class ChatResponse(BaseModel):
    response: str
    conversation_id: str
    metadata: Optional[Dict[str, Any]] = None


class PRDParseRequest(BaseModel):
    conversation_id: str
    tenant_schema: str


class PRDParseResponse(BaseModel):
    extracted_text: str
    parsed_requirements: Dict[str, Any]
    conversation_id: str


class ThemeGenerationRequest(BaseModel):
    conversation_id: str
    tenant_schema: str
    requirements: Dict[str, Any]
    previous_theme: Optional[Dict[str, Any]] = None
    modification_request: Optional[str] = None


class ThemeGenerationResponse(BaseModel):
    theme_config: Dict[str, Any]
    explanation: str
    conversation_id: str
    version: int


# Health check
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "genai-theme-service",
        "llm_provider": settings.llm_provider
    }


# Chat endpoint
@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Handle conversational chat messages.
    Can be used for clarifying requirements, answering questions, etc.
    """
    try:
        response = await llm_service.chat(
            message=request.message,
            conversation_id=request.conversation_id,
            context=request.context
        )
        
        return ChatResponse(
            response=response["message"],
            conversation_id=request.conversation_id,
            metadata=response.get("metadata", {})
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Document upload and parsing
@app.post("/api/parse-prd", response_model=PRDParseResponse)
async def parse_prd(
    file: UploadFile = File(...),
    conversation_id: str = None,
    tenant_schema: str = None
):
    """
    Parse PRD document and extract requirements.
    Supports PDF, DOCX, TXT, MD formats.
    """
    try:
        # Save uploaded file temporarily
        file_path = f"/tmp/{file.filename}"
        with open(file_path, "wb") as buffer:
            content = await file.read()
            buffer.write(content)
        
        # Extract text from document
        extracted_text = document_parser.extract_text(file_path, file.filename)
        
        # Parse requirements using LLM
        parsed_requirements = await llm_service.parse_requirements(
            extracted_text,
            conversation_id
        )
        
        # Clean up
        os.remove(file_path)
        
        return PRDParseResponse(
            extracted_text=extracted_text,
            parsed_requirements=parsed_requirements,
            conversation_id=conversation_id
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Theme generation
@app.post("/api/generate-theme", response_model=ThemeGenerationResponse)
async def generate_theme(request: ThemeGenerationRequest):
    """
    Generate theme based on requirements.
    Can be initial generation or modification of existing theme.
    """
    try:
        if request.previous_theme and request.modification_request:
            # Modify existing theme
            result = await theme_generator.modify_theme(
                previous_theme=request.previous_theme,
                modification_request=request.modification_request,
                requirements=request.requirements,
                conversation_id=request.conversation_id
            )
        else:
            # Generate new theme
            result = await theme_generator.generate_theme(
                requirements=request.requirements,
                conversation_id=request.conversation_id
            )
        
        return ThemeGenerationResponse(
            theme_config=result["theme_config"],
            explanation=result["explanation"],
            conversation_id=request.conversation_id,
            version=result.get("version", 1)
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Test endpoint for quick testing
@app.post("/api/test-llm")
async def test_llm(message: str):
    """Test LLM connectivity"""
    try:
        response = await llm_service.simple_chat(message)
        return {"response": response}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.service_host,
        port=settings.service_port,
        reload=settings.debug
    )
