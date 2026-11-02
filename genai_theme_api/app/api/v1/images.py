"""Image fetching API endpoints."""

from fastapi import APIRouter, HTTPException
import logging
import random

from app.schemas import (
    ImageFetchRequest,
    ImageFetchResponse,
    ErrorResponse
)
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


# Mock image URLs for development
MOCK_IMAGES = {
    "jewelry": [
        "https://images.unsplash.com/photo-1515562141207-7a88fb7ce338",
        "https://images.unsplash.com/photo-1535632066927-ab7c9ab60908",
        "https://images.unsplash.com/photo-1611591437281-460bfbe1220a",
        "https://images.unsplash.com/photo-1599643478518-a784e5dc4c8f",
        "https://images.unsplash.com/photo-1603561596112-0a132b757442"
    ],
    "fashion": [
        "https://images.unsplash.com/photo-1490481651871-ab68de25d43d",
        "https://images.unsplash.com/photo-1483985988355-763728e1935b",
        "https://images.unsplash.com/photo-1445205170230-053b83016050",
        "https://images.unsplash.com/photo-1558769132-cb1aea3b3e0e",
        "https://images.unsplash.com/photo-1467043237213-65f2da53396f"
    ],
    "electronics": [
        "https://images.unsplash.com/photo-1498049794561-7780e7231661",
        "https://images.unsplash.com/photo-1550009158-9ebf69173e03",
        "https://images.unsplash.com/photo-1526738549149-8e07eca6c147",
        "https://images.unsplash.com/photo-1531297484001-80022131f5a1",
        "https://images.unsplash.com/photo-1496181133206-80ce9b88a853"
    ],
    "food": [
        "https://images.unsplash.com/photo-1504674900247-0877df9cc836",
        "https://images.unsplash.com/photo-1493770348161-369560ae357d",
        "https://images.unsplash.com/photo-1546069901-ba9599a7e63c",
        "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445",
        "https://images.unsplash.com/photo-1476224203421-9ac39bcb3327"
    ],
    "tech": [
        "https://images.unsplash.com/photo-1518770660439-4636190af475",
        "https://images.unsplash.com/photo-1519389950473-47ba0277781c",
        "https://images.unsplash.com/photo-1504639725590-34d0984388bd",
        "https://images.unsplash.com/photo-1498050108023-c5249f4df085",
        "https://images.unsplash.com/photo-1522071820081-009f0129c71c"
    ],
    "sports": [
        "https://images.unsplash.com/photo-1461896836934-ffe607ba8211",
        "https://images.unsplash.com/photo-1517649763962-0c623066013b",
        "https://images.unsplash.com/photo-1526676037777-05a232554f77",
        "https://images.unsplash.com/photo-1452626038306-9aae5e071dd3",
        "https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b"
    ],
    "kids": [
        "https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4",
        "https://images.unsplash.com/photo-1596461404969-9ae70f2830c1",
        "https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4",
        "https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9",
        "https://images.unsplash.com/photo-1558877385-1c8e8b5c8c9d"
    ],
    "general": [
        "https://images.unsplash.com/photo-1441986300917-64674bd600d8",
        "https://images.unsplash.com/photo-1472851294608-062f824d29cc",
        "https://images.unsplash.com/photo-1534452203293-494d7ddbf7e0",
        "https://images.unsplash.com/photo-1555421689-d68471e189f2",
        "https://images.unsplash.com/photo-1573855619003-97b4799dcd8b"
    ]
}


def get_category_from_keywords(keywords: list) -> str:
    """Determine image category from keywords."""
    keyword_str = " ".join(keywords).lower()
    
    # Category mapping
    if any(k in keyword_str for k in ["jewelry", "jewel", "diamond", "gold", "ring"]):
        return "jewelry"
    elif any(k in keyword_str for k in ["fashion", "clothing", "apparel", "dress"]):
        return "fashion"
    elif any(k in keyword_str for k in ["electronics", "gadget", "device", "phone"]):
        return "electronics"
    elif any(k in keyword_str for k in ["food", "restaurant", "cafe", "bakery"]):
        return "food"
    elif any(k in keyword_str for k in ["tech", "software", "computer", "coding"]):
        return "tech"
    elif any(k in keyword_str for k in ["sports", "fitness", "gym", "athletic"]):
        return "sports"
    elif any(k in keyword_str for k in ["kids", "children", "toys", "baby"]):
        return "kids"
    else:
        return "general"


@router.post(
    "/images/fetch",
    response_model=ImageFetchResponse,
    summary="Fetch relevant images",
    description="Fetch high-quality images from Unsplash based on keywords"
)
async def fetch_images(request: ImageFetchRequest):
    """
    Fetch images based on keywords.
    
    In mock mode:
    - Returns curated mock images based on keyword categories
    - No API calls made to Unsplash
    
    In production mode:
    - Calls Unsplash API with keywords
    - Returns high-quality, relevant images
    - Respects rate limits (50 requests/hour free tier)
    
    Parameters:
    - keywords: List of search terms (e.g., ["jewelry", "luxury", "gold"])
    - count: Number of images to fetch (1-10)
    - orientation: "landscape", "portrait", or "squarish"
    """
    try:
        logger.info(f"Fetching images for keywords: {request.keywords}")
        
        if settings.mock_image_mode:
            # Mock mode - return curated images
            category = get_category_from_keywords(request.keywords)
            available_images = MOCK_IMAGES.get(category, MOCK_IMAGES["general"])
            
            # Select random images
            count = min(request.count, len(available_images))
            selected_images = random.sample(available_images, count)
            
            # Format response
            images = []
            for i, url in enumerate(selected_images):
                keyword_desc = ", ".join(request.keywords[:2])
                images.append({
                    "url": url,
                    "thumbnail": f"{url}?w=400&h=300&fit=crop",
                    "alt": f"{keyword_desc} - Image {i+1}",
                    "photographer": "Unsplash Contributor",
                    "photographer_url": "https://unsplash.com/@contributor"
                })
            
            return ImageFetchResponse(
                images=images,
                total_found=len(images)
            )
        
        else:
            # Production mode - call Unsplash API
            # This would use the actual Unsplash API client
            raise HTTPException(
                status_code=501,
                detail={
                    "error": {
                        "code": "NOT_IMPLEMENTED",
                        "message": "Real Unsplash integration not yet implemented",
                        "suggestion": "Set MOCK_IMAGE_MODE=True in .env for development"
                    }
                }
            )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching images: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "IMAGE_FETCH_ERROR",
                    "message": "Failed to fetch images",
                    "details": str(e)
                }
            }
        )


@router.get(
    "/images/categories",
    summary="Get available image categories",
    description="Get list of available image categories for reference"
)
async def get_image_categories():
    """
    Get available image categories.
    
    Returns a list of supported image categories with example keywords.
    Useful for understanding what types of images can be fetched.
    """
    categories = {
        "jewelry": {
            "keywords": ["jewelry", "jewel", "diamond", "gold", "ring", "necklace"],
            "description": "Luxury jewelry and accessories"
        },
        "fashion": {
            "keywords": ["fashion", "clothing", "apparel", "dress", "style"],
            "description": "Fashion and clothing items"
        },
        "electronics": {
            "keywords": ["electronics", "gadget", "device", "phone", "computer"],
            "description": "Electronic devices and gadgets"
        },
        "food": {
            "keywords": ["food", "restaurant", "cafe", "bakery", "cuisine"],
            "description": "Food and dining"
        },
        "tech": {
            "keywords": ["tech", "software", "coding", "workspace", "startup"],
            "description": "Technology and software"
        },
        "sports": {
            "keywords": ["sports", "fitness", "gym", "athletic", "exercise"],
            "description": "Sports and fitness"
        },
        "kids": {
            "keywords": ["kids", "children", "toys", "baby", "playground"],
            "description": "Kids and family products"
        },
        "general": {
            "keywords": ["store", "shop", "retail", "business", "product"],
            "description": "General retail and business"
        }
    }
    
    return {
        "categories": categories,
        "total": len(categories),
        "mock_mode": settings.mock_image_mode
    }
