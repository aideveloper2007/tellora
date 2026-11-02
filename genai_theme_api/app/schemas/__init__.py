"""Pydantic schemas for API request/response validation."""

from pydantic import BaseModel, Field, validator
from typing import Optional, Dict, Any, List
from datetime import datetime
from enum import Enum


# Store type is now dynamic - accepts any string describing the store
# No longer limited to predefined categories


class TemplateType(str, Enum):
    """Available theme templates."""
    LUXURY = "template_luxury_001"
    MODERN = "template_modern_002"
    PLAYFUL = "template_playful_003"


class ConversationStatus(str, Enum):
    """Conversation status states."""
    ACTIVE = "active"
    WAITING = "waiting"
    COMPLETED = "completed"
    ERROR = "error"


class ThemeStatus(str, Enum):
    """Theme generation status states."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    VALIDATING = "validating"
    FETCHING_IMAGES = "fetching_images"
    COMPLETED = "completed"
    FAILED = "failed"


# ========== Conversation Schemas ==========

class ConversationStartRequest(BaseModel):
    """Request to start a new conversation."""
    user_id: str = Field(..., description="Unique identifier for the user")
    tenant_id: str = Field(..., description="Tenant identifier from Rails app")
    
    class Config:
        json_schema_extra = {
            "example": {
                "user_id": "user_123",
                "tenant_id": "mystore"
            }
        }


class ConversationStartResponse(BaseModel):
    """Response after starting a conversation."""
    conversation_id: str = Field(..., description="Unique conversation ID")
    message: str = Field(..., description="Welcome message")
    suggestions: List[str] = Field(..., description="Suggested next steps")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    
    class Config:
        json_schema_extra = {
            "example": {
                "conversation_id": "conv_abc123",
                "message": "Welcome! I'm your AI theme designer.",
                "suggestions": [
                    "Tell me about your store",
                    "Upload a PRD document",
                    "Generate a theme based on my store type"
                ],
                "created_at": "2026-01-08T10:30:00Z"
            }
        }


class ConversationMessageRequest(BaseModel):
    """Request to send a message in conversation."""
    message: str = Field(..., min_length=1, max_length=2000, description="User message")
    context: Optional[Dict[str, Any]] = Field(default=None, description="Additional context")
    
    class Config:
        json_schema_extra = {
            "example": {
                "message": "I run a luxury jewelry store targeting high-end customers",
                "context": {
                    "store_type": "jewelry",
                    "target_audience": "luxury"
                }
            }
        }


class ConversationMessageResponse(BaseModel):
    """Response to a conversation message."""
    message: str = Field(..., description="AI assistant response")
    extracted_info: Dict[str, Any] = Field(..., description="Extracted information")
    suggestions: List[str] = Field(default_factory=list, description="Next step suggestions")
    ready_for_generation: bool = Field(default=False, description="Whether enough info is gathered")
    
    class Config:
        json_schema_extra = {
            "example": {
                "message": "Perfect! I understand you run a luxury jewelry store...",
                "extracted_info": {
                    "store_type": "jewelry",
                    "style_preferences": ["elegant", "metallic", "sophisticated"],
                    "target_audience": "luxury"
                },
                "suggestions": [
                    "Generate theme now",
                    "Tell me more about your products",
                    "Upload a brand document"
                ],
                "ready_for_generation": True
            }
        }


class PRDUploadResponse(BaseModel):
    """Response after PRD upload."""
    message: str = Field(..., description="Upload confirmation message")
    extracted_info: Dict[str, Any] = Field(..., description="Information extracted from PRD")
    file_name: str = Field(..., description="Uploaded file name")
    ready_for_generation: bool = Field(default=False, description="Whether ready to generate")
    
    class Config:
        json_schema_extra = {
            "example": {
                "message": "Successfully processed your PRD document!",
                "extracted_info": {
                    "store_name": "Luxe Jewels",
                    "store_type": "jewelry",
                    "brand_colors": ["#C0C0C0", "#FFD700"],
                    "style_keywords": ["elegant", "timeless", "luxury"]
                },
                "file_name": "brand_requirements.pdf",
                "ready_for_generation": True
            }
        }


# ========== Theme Generation Schemas ==========

class ThemeGenerateRequest(BaseModel):
    """Request to generate a theme."""
    conversation_id: Optional[str] = Field(None, description="Optional conversation ID")
    store_type: str = Field(..., description="Type of store - any description (e.g., 'jewelry', 'pet supplies', 'organic skincare', 'vintage books')")
    template: Optional[TemplateType] = Field(None, description="Preferred template (optional)")
    requirements: Dict[str, Any] = Field(..., description="Theme requirements")
    tenant_id: str = Field(..., description="Tenant identifier")
    use_real_llm: Optional[bool] = Field(None, description="Override to use real LLM (Claude) or mock LLM")
    
    @validator('requirements')
    def validate_requirements(cls, v):
        """Validate requirements dictionary."""
        # store_name is recommended but not required (can be generated)
        # Just ensure we have some basic info
        if not v:
            raise ValueError("Requirements cannot be empty")
        return v
    
    class Config:
        json_schema_extra = {
            "example": {
                "conversation_id": "conv_abc123",
                "store_type": "luxury jewelry boutique",
                "template": "template_luxury_001",
                "requirements": {
                    "store_name": "Luxe Jewels",
                    "store_description": "High-end jewelry store specializing in custom engagement rings and fine watches",
                    "style_keywords": ["elegant", "luxurious", "timeless"],
                    "brand_colors": ["#C0C0C0", "#FFD700"],
                    "target_audience": "luxury shoppers",
                    "products": ["rings", "necklaces", "bracelets"]
                },
                "tenant_id": "mystore"
            }
        }


class ThemeGenerateResponse(BaseModel):
    """Response after initiating theme generation."""
    theme_id: str = Field(..., description="Unique theme ID")
    status: ThemeStatus = Field(..., description="Generation status")
    message: str = Field(..., description="Status message")
    estimated_time_seconds: int = Field(..., description="Estimated completion time")
    
    class Config:
        json_schema_extra = {
            "example": {
                "theme_id": "theme_xyz789",
                "status": "in_progress",
                "message": "Generating your theme... This may take 20-30 seconds.",
                "estimated_time_seconds": 25
            }
        }


class ThemeData(BaseModel):
    """Complete theme data structure."""
    colors: Optional[Dict[str, str]] = Field(None, description="Color palette")
    typography: Optional[Dict[str, Any]] = Field(None, description="Typography settings")
    layout: Optional[Dict[str, Any]] = Field(None, description="Layout configuration")
    components: Optional[Dict[str, Any]] = Field(None, description="Component styles")
    images: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Image data with hero and products")
    css: Optional[str] = Field(None, description="Generated CSS")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional metadata")


class ThemeStatusResponse(BaseModel):
    """Response for theme status check."""
    theme_id: str = Field(..., description="Theme ID")
    status: ThemeStatus = Field(..., description="Current status")
    progress: int = Field(..., ge=0, le=100, description="Progress percentage")
    theme_data: Optional[ThemeData] = Field(None, description="Theme data if completed")
    validation_report: Optional[Dict[str, Any]] = Field(None, description="Validation results")
    error: Optional[str] = Field(None, description="Error message if failed")
    
    class Config:
        json_schema_extra = {
            "example": {
                "theme_id": "theme_xyz789",
                "status": "completed",
                "progress": 100,
                "theme_data": {
                    "colors": {
                        "primary": "#C0C0C0",
                        "secondary": "#FFD700",
                        "accent": "#000000"
                    },
                    "typography": {
                        "heading_font": "Playfair Display",
                        "body_font": "Montserrat"
                    },
                    "css": "/* Generated CSS */"
                },
                "validation_report": {
                    "overall_score": 0.95,
                    "checks_passed": 7,
                    "checks_total": 7
                }
            }
        }


class ThemeRefineRequest(BaseModel):
    """Request to refine an existing theme."""
    feedback: str = Field(..., min_length=10, description="Refinement feedback")
    specific_changes: Optional[Dict[str, Any]] = Field(None, description="Specific changes requested")
    
    class Config:
        json_schema_extra = {
            "example": {
                "feedback": "Make the colors more vibrant and use a bolder heading font",
                "specific_changes": {
                    "colors": {
                        "primary": "#D4AF37"
                    },
                    "typography": {
                        "heading_font": "Bodoni MT"
                    }
                }
            }
        }


class ThemeRefineResponse(BaseModel):
    """Response after theme refinement."""
    theme_id: str = Field(..., description="Updated theme ID")
    status: ThemeStatus = Field(..., description="Refinement status")
    message: str = Field(..., description="Status message")
    changes_applied: List[str] = Field(..., description="List of changes applied")


# ========== Image Schemas ==========

class ImageFetchRequest(BaseModel):
    """Request to fetch images."""
    keywords: List[str] = Field(..., min_items=1, description="Search keywords")
    count: int = Field(default=5, ge=1, le=10, description="Number of images")
    orientation: Optional[str] = Field("landscape", description="Image orientation")
    
    class Config:
        json_schema_extra = {
            "example": {
                "keywords": ["jewelry", "luxury", "gold"],
                "count": 5,
                "orientation": "landscape"
            }
        }


class ImageFetchResponse(BaseModel):
    """Response with fetched images."""
    images: List[Dict[str, str]] = Field(..., description="List of image URLs")
    total_found: int = Field(..., description="Total images found")
    
    class Config:
        json_schema_extra = {
            "example": {
                "images": [
                    {
                        "url": "https://images.unsplash.com/photo-123",
                        "thumbnail": "https://images.unsplash.com/photo-123?w=400",
                        "alt": "Luxury gold jewelry display"
                    }
                ],
                "total_found": 5
            }
        }


# ========== Validation Schemas ==========

class ThemeValidateRequest(BaseModel):
    """Request to validate a theme."""
    theme_data: ThemeData = Field(..., description="Theme data to validate")
    template: TemplateType = Field(..., description="Template to validate against")
    store_type: str = Field(..., description="Store type - any description")


class ValidationResult(BaseModel):
    """Validation result for a single check."""
    check_name: str = Field(..., description="Name of validation check")
    passed: bool = Field(..., description="Whether check passed")
    score: float = Field(..., ge=0.0, le=1.0, description="Score (0-1)")
    message: str = Field(..., description="Result message")
    suggestions: List[str] = Field(default_factory=list, description="Improvement suggestions")


class ThemeValidateResponse(BaseModel):
    """Response after theme validation."""
    valid: bool = Field(..., description="Overall validation result")
    overall_score: float = Field(..., ge=0.0, le=1.0, description="Overall quality score")
    checks: List[ValidationResult] = Field(..., description="Individual validation results")
    summary: str = Field(..., description="Validation summary")


# ========== Error Schemas ==========

class ErrorResponse(BaseModel):
    """Standard error response."""
    error: Dict[str, Any] = Field(..., description="Error details")
    
    class Config:
        json_schema_extra = {
            "example": {
                "error": {
                    "code": "VALIDATION_ERROR",
                    "message": "Invalid request",
                    "details": {
                        "field": "requirements",
                        "message": "Requirements cannot be empty"
                    }
                }
            }
        }
