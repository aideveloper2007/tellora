"""Pixabay image service for fetching product images."""

import httpx
from typing import List, Dict, Any
import logging

logger = logging.getLogger(__name__)


class PixabayService:
    """Service for fetching images from Pixabay API."""
    
    BASE_URL = "https://pixabay.com/api/"
    
    # Keywords mapping for different store types
    STORE_TYPE_KEYWORDS = {
        "jewelry": ["jewelry", "diamond+ring", "gold+necklace", "luxury+watch", "pearl+earrings"],
        "fashion": ["fashion", "clothing", "dress", "style", "boutique"],
        "electronics": ["electronics", "gadgets", "smartphone", "laptop", "technology"],
        "tech": ["technology", "computer", "software", "innovation", "digital"],
        "food": ["food", "cuisine", "dish", "meal", "gourmet"],
        "kids": ["toys", "children", "playground", "kids+fashion", "baby"],
        "sports": ["sports", "fitness", "athletic", "gym", "exercise"],
        "home": ["home+decor", "furniture", "interior+design", "garden", "plants"],
        "general": ["product", "shopping", "retail", "store", "display"]
    }
    
    def __init__(self, api_key: str):
        """Initialize Pixabay service with API key."""
        self.api_key = api_key
        self.client = httpx.AsyncClient(timeout=30.0)
    
    async def fetch_images(
        self,
        store_type: str = "general",
        count: int = 8,
        image_type: str = "photo"
    ) -> List[Dict[str, Any]]:
        """
        Fetch images for a store type.
        
        Args:
            store_type: Type of store (jewelry, fashion, etc.)
            count: Number of images to fetch
            image_type: Type of images (photo, illustration, vector)
            
        Returns:
            List of image dictionaries with URLs and metadata
        """
        try:
            # Get keywords for store type
            keywords = self.STORE_TYPE_KEYWORDS.get(store_type, self.STORE_TYPE_KEYWORDS["general"])
            
            # Fetch images for different keywords
            all_images = []
            # Pixabay free tier requires minimum per_page=3
            images_per_keyword = max(3, count // len(keywords))
            
            for keyword in keywords[:3]:  # Use first 3 keywords for variety
                images = await self._fetch_by_keyword(
                    keyword=keyword,
                    per_page=images_per_keyword,
                    image_type=image_type
                )
                all_images.extend(images)
                
                if len(all_images) >= count:
                    break
            
            # Return requested number of images
            return all_images[:count]
            
        except Exception as e:
            logger.error(f"Error fetching Pixabay images: {e}")
            # Return placeholder images on error
            return self._get_placeholder_images(count)
    
    async def _fetch_by_keyword(
        self,
        keyword: str,
        per_page: int = 3,
        image_type: str = "photo"
    ) -> List[Dict[str, Any]]:
        """Fetch images for a specific keyword."""
        try:
            params = {
                "key": self.api_key,
                "q": keyword,
                "image_type": image_type,
                "per_page": per_page,
                "safesearch": "true"
            }
            
            response = await self.client.get(self.BASE_URL, params=params)
            response.raise_for_status()
            
            data = response.json()
            
            # Transform Pixabay response to our format
            images = []
            for hit in data.get("hits", []):
                images.append({
                    "url": hit.get("largeImageURL"),
                    "preview_url": hit.get("webformatURL"),
                    "thumbnail_url": hit.get("previewURL"),
                    "width": hit.get("imageWidth"),
                    "height": hit.get("imageHeight"),
                    "type": "product",
                    "source": "pixabay",
                    "tags": hit.get("tags", "").split(", "),
                    "photographer": hit.get("user"),
                    "photographer_url": f"https://pixabay.com/users/{hit.get('user')}-{hit.get('user_id')}/"
                })
            
            return images
            
        except Exception as e:
            logger.error(f"Error fetching images for keyword '{keyword}': {e}")
            return []
    
    async def fetch_images_by_search(
        self,
        search_term: str,
        count: int = 6,
        image_type: str = "photo"
    ) -> List[Dict[str, Any]]:
        """
        Fetch images using a custom search term.
        
        Args:
            search_term: Custom search query
            count: Number of images to fetch
            image_type: Type of images (photo, illustration, vector)
            
        Returns:
            List of image dictionaries
        """
        try:
            per_page = max(3, count)  # Pixabay minimum is 3
            
            params = {
                "key": self.api_key,
                "q": search_term,
                "image_type": image_type,
                "per_page": per_page,
                "safesearch": "true"
            }
            
            response = await self.client.get(self.BASE_URL, params=params)
            response.raise_for_status()
            
            data = response.json()
            
            # Transform Pixabay response
            images = []
            for hit in data.get("hits", []):
                images.append({
                    "url": hit.get("largeImageURL"),
                    "preview_url": hit.get("webformatURL"),
                    "thumbnail_url": hit.get("previewURL"),
                    "width": hit.get("imageWidth"),
                    "height": hit.get("imageHeight"),
                    "type": "product",
                    "source": "pixabay",
                    "tags": hit.get("tags", "").split(", ") if hit.get("tags") else [],
                    "photographer": hit.get("user"),
                    "photographer_url": f"https://pixabay.com/users/{hit.get('user')}-{hit.get('user_id')}/" if hit.get('user') else ""
                })
            
            return images[:count]
            
        except Exception as e:
            logger.error(f"Error fetching images for search '{search_term}': {e}")
            return []
    
    def _get_placeholder_images(self, count: int) -> List[Dict[str, Any]]:
        """Return placeholder images when API fails."""
        placeholders = []
        for i in range(count):
            placeholders.append({
                "url": f"https://placehold.co/800x600/CCCCCC/666666?text=Product+{i+1}",
                "preview_url": f"https://placehold.co/400x300/CCCCCC/666666?text=Product+{i+1}",
                "thumbnail_url": f"https://placehold.co/150x150/CCCCCC/666666?text=Product+{i+1}",
                "width": 800,
                "height": 600,
                "type": "placeholder",
                "source": "placeholder",
                "tags": [],
                "photographer": "Placeholder",
                "photographer_url": ""
            })
        return placeholders
    
    async def fetch_hero_image(self, store_type: str = "general") -> Dict[str, Any]:
        """
        Fetch a hero/banner image for store type.
        
        Returns a landscape image suitable for hero sections.
        """
        try:
            keywords = self.STORE_TYPE_KEYWORDS.get(store_type, ["store", "shop"])
            keyword = keywords[0]  # Use first keyword for hero
            
            params = {
                "key": self.api_key,
                "q": keyword,
                "image_type": "photo",
                "per_page": 3,  # Pixabay free tier minimum
                "safesearch": "true",
                "min_width": 1200
            }
            
            response = await self.client.get(self.BASE_URL, params=params)
            response.raise_for_status()
            
            data = response.json()
            hits = data.get("hits", [])
            
            if hits:
                hit = hits[0]
                return {
                    "url": hit.get("largeImageURL"),
                    "preview_url": hit.get("webformatURL"),
                    "width": hit.get("imageWidth"),
                    "height": hit.get("imageHeight"),
                    "type": "hero",
                    "source": "pixabay",
                    "tags": hit.get("tags", "").split(", "),
                    "photographer": hit.get("user"),
                    "photographer_url": f"https://pixabay.com/users/{hit.get('user')}-{hit.get('user_id')}/"
                }
            else:
                return self._get_placeholder_hero()
                
        except Exception as e:
            logger.error(f"Error fetching hero image: {e}")
            return self._get_placeholder_hero()
    
    def _get_placeholder_hero(self) -> Dict[str, Any]:
        """Return placeholder hero image."""
        return {
            "url": "https://placehold.co/1600x900/CCCCCC/666666?text=Hero+Banner",
            "preview_url": "https://placehold.co/800x450/CCCCCC/666666?text=Hero+Banner",
            "width": 1600,
            "height": 900,
            "type": "hero",
            "source": "placeholder",
            "tags": [],
            "photographer": "Placeholder",
            "photographer_url": ""
        }
    
    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()
