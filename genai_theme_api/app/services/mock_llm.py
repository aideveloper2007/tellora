"""Mock LLM service for development and testing without API keys."""

import json
import random
from typing import Dict, Any, List, Optional
import time


class MockLLMService:
    """Mock LLM service that simulates Claude API responses."""
    
    def __init__(self, pixabay_service=None):
        """Initialize mock LLM service with optional Pixabay service."""
        self.conversation_history = {}
        self.pixabay_service = pixabay_service
    
    # Template definitions matching our API spec
    TEMPLATES = {
        "template_luxury_001": {
            "name": "Luxury",
            "colors": {
                "primary": "#C0C0C0",  # Silver
                "secondary": "#FFD700",  # Gold
                "accent": "#000000",  # Black
                "background": "#FFFFFF",
                "text": "#2C2C2C"
            },
            "typography": {
                "heading_font": "Playfair Display",
                "body_font": "Montserrat",
                "heading_weight": "700",
                "body_weight": "400"
            },
            "style": "elegant, sophisticated, luxury"
        },
        "template_modern_002": {
            "name": "Modern",
            "colors": {
                "primary": "#4A90E2",  # Modern Blue
                "secondary": "#50E3C2",  # Teal
                "accent": "#F5A623",  # Orange
                "background": "#F8F9FA",
                "text": "#333333"
            },
            "typography": {
                "heading_font": "Inter",
                "body_font": "Roboto",
                "heading_weight": "700",
                "body_weight": "400"
            },
            "style": "clean, modern, minimalist"
        },
        "template_playful_003": {
            "name": "Playful",
            "colors": {
                "primary": "#FF6B6B",  # Coral Red
                "secondary": "#4ECDC4",  # Turquoise
                "accent": "#FFE66D",  # Yellow
                "background": "#FFFFFF",
                "text": "#2C3E50"
            },
            "typography": {
                "heading_font": "Fredoka One",
                "body_font": "Open Sans",
                "heading_weight": "600",
                "body_weight": "400"
            },
            "style": "fun, vibrant, energetic"
        }
    }
    
    # Store type to template mapping
    STORE_TEMPLATE_MAP = {
        "jewelry": "template_luxury_001",
        "fashion": "template_luxury_001",
        "electronics": "template_modern_002",
        "tech": "template_modern_002",
        "general": "template_modern_002",
        "food": "template_playful_003",
        "kids": "template_playful_003",
        "sports": "template_playful_003",
        "home": "template_modern_002"
    }
    
    async def start_conversation(self, user_id: str, tenant_id: str) -> Dict[str, Any]:
        """Start a new conversation."""
        conversation_id = f"conv_{random.randint(100000, 999999)}"
        
        self.conversation_history[conversation_id] = {
            "user_id": user_id,
            "tenant_id": tenant_id,
            "messages": [],
            "extracted_info": {}
        }
        
        return {
            "conversation_id": conversation_id,
            "message": (
                "Welcome! I'm your AI theme designer. I can help you create a beautiful "
                "theme for your online store. You can either:\n"
                "1. Tell me about your store in a conversation\n"
                "2. Upload a PRD document with your requirements\n"
                "3. Provide store details directly for quick generation"
            ),
            "suggestions": [
                "Tell me about your store",
                "Upload a PRD document",
                "I run a jewelry store",
                "Generate theme for fashion store"
            ]
        }
    
    async def send_message(
        self, 
        conversation_id: str, 
        message: str,
        context: Dict[str, Any] = None
    ) -> Dict[str, Any]:
        """Process a conversation message."""
        if conversation_id not in self.conversation_history:
            raise ValueError("Conversation not found")
        
        # Store message
        self.conversation_history[conversation_id]["messages"].append({
            "role": "user",
            "content": message
        })
        
        # Extract information from message (simple keyword matching)
        extracted = self._extract_info_from_message(message, context)
        
        # Update conversation info
        self.conversation_history[conversation_id]["extracted_info"].update(extracted)
        
        # Generate response
        response_msg = self._generate_response_message(extracted)
        
        # Check if ready for generation
        current_info = self.conversation_history[conversation_id]["extracted_info"]
        # Ready if we have store_type, store_name, OR style keywords (enough to generate a generic theme)
        ready = (
            "store_type" in current_info or 
            "store_name" in current_info or
            ("style_keywords" in current_info and len(current_info["style_keywords"]) > 0)
        )
        
        return {
            "message": response_msg,
            "extracted_info": current_info,
            "suggestions": self._get_suggestions(current_info, ready),
            "ready_for_generation": ready
        }
    
    async def process_prd(
        self,
        conversation_id: str,
        file_content: str,
        file_name: str
    ) -> Dict[str, Any]:
        """Process a PRD document."""
        if conversation_id not in self.conversation_history:
            raise ValueError("Conversation not found")
        
        # Simulate PRD processing with delay
        await self._simulate_processing_delay(1.0)
        
        # Extract info from PRD (mock extraction)
        extracted = self._extract_info_from_prd(file_content)
        
        # Update conversation
        self.conversation_history[conversation_id]["extracted_info"].update(extracted)
        
        return {
            "message": f"Successfully processed your PRD document '{file_name}'! I've extracted key information about your store.",
            "extracted_info": extracted,
            "file_name": file_name,
            "ready_for_generation": True
        }
    
    async def generate_theme(
        self,
        store_type: str,
        requirements: Dict[str, Any],
        template: str = None
    ) -> Dict[str, Any]:
        """Generate a complete theme with images."""
        # Simulate generation time
        await self._simulate_processing_delay(2.0)
        
        # Check if there's extracted info from PRD that should override requirements
        conversation_id = requirements.get("context", [{}])[0].get("conversation_id") if requirements.get("context") else None
        if conversation_id and conversation_id in self.conversation_history:
            extracted_info = self.conversation_history[conversation_id].get("extracted_info", {})
            
            # Override store_type if extracted from PRD
            if extracted_info.get("store_type"):
                original_store_type = store_type
                store_type = extracted_info["store_type"]
                print(f"DEBUG: Overriding store_type from '{original_store_type}' to '{store_type}' based on PRD")
            
            # Merge ALL comprehensive design tokens from PRD
            design_token_keys = [
                "colors", "typography", "spacing", "borders", "shadows",
                "effects", "buttons", "cards", "layout", "design_preferences",
                "style_keywords"
            ]
            
            for key in design_token_keys:
                if extracted_info.get(key):
                    requirements[key] = extracted_info[key]
                    print(f"DEBUG: Using PRD {key}: {str(extracted_info[key])[:100]}...")
        
        # Select template
        if not template:
            template = self.STORE_TEMPLATE_MAP.get(store_type, "template_modern_002")
        
        base_template = self.TEMPLATES[template]
        layout = self._generate_layout(store_type, requirements)
        
        # Fetch images if Pixabay service is available
        images = []
        hero_image = None
        
        print(f"DEBUG: pixabay_service is {'available' if self.pixabay_service else 'None'}")
        
        if self.pixabay_service:
            try:
                # Determine number of product images based on layout
                num_products = layout["product_grid"]["columns_desktop"] * 2
                
                print(f"DEBUG: Fetching {num_products} product images for {store_type}")
                
                # Fetch product images
                images = await self.pixabay_service.fetch_images(
                    store_type=store_type,
                    count=num_products
                )
                
                print(f"DEBUG: Fetched {len(images)} product images")
                
                # Fetch hero image
                hero_image = await self.pixabay_service.fetch_hero_image(store_type=store_type)
                
                print(f"DEBUG: Hero image fetched: {hero_image is not None}")
                
            except Exception as e:
                print(f"Warning: Could not fetch images: {e}")
                import traceback
                traceback.print_exc()
                images = []
                hero_image = None
        
        # Generate theme data
        # Apply structured colors from PRD if available (takes priority)
        if requirements.get("colors") and isinstance(requirements["colors"], dict):
            # Use structured colors directly
            colors = requirements["colors"]
        else:
            # Fallback to old _customize_colors method
            colors = self._customize_colors(base_template["colors"], requirements)
        
        # Apply structured typography from PRD if available (takes priority)
        if requirements.get("typography") and isinstance(requirements["typography"], dict):
            # Use structured typography directly
            typography = requirements["typography"]
        else:
            # Fallback: apply fonts the old way
            typography = base_template["typography"].copy()
            if requirements.get("fonts"):
                fonts = requirements["fonts"]
                if len(fonts) >= 1:
                    typography["heading_font"] = fonts[0]
                if len(fonts) >= 2:
                    typography["body_font"] = fonts[1]
                elif len(fonts) == 1:
                    typography["body_font"] = fonts[0]
        
        theme_data = {
            "colors": colors,
            "typography": typography,
            "layout": layout,
            "components": self._generate_components(base_template),
            "images": {
                "hero": hero_image,
                "products": images
            },
            "css": self._generate_css(base_template, requirements, store_type),
            "metadata": {
                "template": template,
                "store_type": store_type,
                "generated_at": time.time(),
                "version": "1.0.0",
                "requirements": requirements
            }
        }
        
        return theme_data
    
    async def refine_theme(
        self,
        theme_data: Dict[str, Any],
        feedback: str,
        specific_changes: Dict[str, Any] = None
    ) -> Dict[str, Any]:
        """Refine an existing theme based on feedback."""
        # Simulate refinement
        await self._simulate_processing_delay(1.5)
        
        refined_theme = theme_data.copy()
        changes_applied = []
        
        # Apply specific changes if provided
        if specific_changes:
            if "colors" in specific_changes:
                refined_theme["colors"].update(specific_changes["colors"])
                changes_applied.append("Updated color palette")
            
            if "typography" in specific_changes:
                refined_theme["typography"].update(specific_changes["typography"])
                changes_applied.append("Updated typography")
        
        # Parse feedback for general refinements
        if "vibrant" in feedback.lower() or "brighter" in feedback.lower():
            # Make colors more vibrant (mock)
            changes_applied.append("Enhanced color vibrancy")
        
        if "bold" in feedback.lower():
            refined_theme["typography"]["heading_weight"] = "800"
            changes_applied.append("Made headings bolder")
        
        if not changes_applied:
            changes_applied.append("Applied general refinements based on feedback")
        
        return {
            "theme_data": refined_theme,
            "changes_applied": changes_applied
        }
    
    def _extract_info_from_message(
        self, 
        message: str, 
        context: Dict[str, Any] = None
    ) -> Dict[str, Any]:
        """Extract information from user message - handles any store type dynamically."""
        message_lower = message.lower()
        extracted = {}
        
        # Try to extract store type from context - look for descriptive phrases
        # Look for patterns like "I run a X store", "my X business", "X shop"
        import re
        
        # Patterns to detect store type
        store_patterns = [
            r"(?:i run|i have|i own|my|a|an)\s+([a-z\s]+?)\s+(?:store|shop|business|boutique|company)",
            r"(?:sell|selling)\s+([a-z\s]+)",
            r"([a-z\s]+?)\s+(?:ecommerce|e-commerce|online store)",
        ]
        
        for pattern in store_patterns:
            match = re.search(pattern, message_lower)
            if match:
                store_desc = match.group(1).strip()
                if store_desc and len(store_desc.split()) <= 5:  # Reasonable store description
                    extracted["store_type"] = store_desc
                    break
        
        # Fallback: Try keyword matching for common store types
        if "store_type" not in extracted:
            common_stores = {
                "jewelry": ["jewelry", "jewel", "diamond", "gold", "rings", "necklace"],
                "fashion": ["fashion", "clothing", "apparel", "boutique", "dress", "shirts"],
                "electronics": ["electronics", "gadget", "device", "computer", "phone"],
                "tech": ["tech", "software", "saas", "app", "digital"],
                "food": ["food", "restaurant", "cafe", "bakery", "grocery"],
                "kids": ["kids", "children", "toys", "baby"],
                "sports": ["sports", "fitness", "gym", "athletic", "workout"],
                "pet": ["pet", "dog", "cat", "animal"],
                "beauty": ["beauty", "cosmetics", "skincare", "makeup"],
                "home": ["home", "furniture", "decor", "interior"],
                "books": ["book", "library", "reading"],
                "art": ["art", "gallery", "painting", "craft"],
            }
            
            for store_type, keywords in common_stores.items():
                if any(keyword in message_lower for keyword in keywords):
                    extracted["store_type"] = store_type
                    break
        
        # If still no store type, mark as "general" to indicate we need more info
        if "store_type" not in extracted:
            extracted["store_type"] = "general retail"
        
        # Style keywords
        style_keywords = {
            "elegant": ["elegant", "sophisticated", "classy", "refined"],
            "modern": ["modern", "contemporary", "sleek", "current"],
            "luxury": ["luxury", "premium", "high-end", "exclusive"],
            "minimalist": ["minimal", "simple", "clean", "understated"],
            "vibrant": ["vibrant", "colorful", "bold", "bright"],
            "playful": ["playful", "fun", "energetic", "whimsical"],
            "rustic": ["rustic", "vintage", "antique", "traditional"],
            "professional": ["professional", "corporate", "business"]
        }
        
        extracted_styles = []
        for style, keywords in style_keywords.items():
            if any(keyword in message_lower for keyword in keywords):
                extracted_styles.append(style)
        
        if extracted_styles:
            extracted["style_keywords"] = extracted_styles
        
        # Add context if provided
        if context:
            extracted.update(context)
        
        return extracted
    
    def _extract_info_from_prd(self, content: str) -> Dict[str, Any]:
        """Extract comprehensive design system information from PRD using keyword matching."""
        content_lower = content.lower()
        extracted = {}
        
        # Extract store type more dynamically - look for business descriptors
        import re
        
        # Try to find business/store descriptions
        business_patterns = [
            r"(?:we are|we're|company is|business is|store is)\s+(?:a|an)\s+([a-z\s]+?)\s+(?:company|business|store|shop|brand)",
            r"(?:selling|specializing in|focused on)\s+([a-z\s]+)",
            r"([a-z\s]+?)\s+(?:ecommerce|e-commerce|online store|marketplace)",
        ]
        
        for pattern in business_patterns:
            match = re.search(pattern, content_lower)
            if match:
                store_desc = match.group(1).strip()
                if store_desc and len(store_desc.split()) <= 6:
                    extracted["store_type"] = store_desc
                    break
        
        # Fallback to keyword matching if pattern matching failed
        if "store_type" not in extracted:
            common_categories = {
                "luxury jewelry": ["jewelry", "jewel", "gold", "diamond", "precious", "gemstone", "rings"],
                "fashion apparel": ["fashion", "clothing", "apparel", "boutique", "textile", "dress"],
                "electronics": ["electronics", "gadget", "device", "tech hardware", "computer"],
                "technology": ["tech", "software", "saas", "technology", "digital services"],
                "food & beverage": ["food", "restaurant", "cafe", "bakery", "culinary", "catering"],
                "home decor": ["home", "furniture", "decor", "interior", "living space"],
                "fitness & sports": ["sports", "fitness", "gym", "athletic", "wellness"],
                "beauty & cosmetics": ["beauty", "cosmetics", "skincare", "makeup", "spa"],
                "pet supplies": ["pet", "dog", "cat", "animal care", "veterinary"],
                "books & media": ["book", "library", "reading", "publishing", "literature"],
                "arts & crafts": ["art", "gallery", "painting", "craft", "handmade"],
                "kids & toys": ["kids", "children", "toys", "baby", "educational"],
                "organic products": ["organic", "natural", "eco", "sustainable", "green"],
            }
            
            best_match = None
            max_matches = 0
            
            for category, keywords in common_categories.items():
                matches = sum(1 for keyword in keywords if keyword in content_lower)
                if matches > max_matches:
                    max_matches = matches
                    best_match = category
            
            if best_match and max_matches >= 2:  # At least 2 keyword matches
                extracted["store_type"] = best_match
            else:
                extracted["store_type"] = "general retail"
        
        for store_type, keywords in store_types.items():
            if any(keyword in content_lower for keyword in keywords):
                extracted["store_type"] = store_type
                break
        
        if "store_type" not in extracted:
            extracted["store_type"] = "general"
        
        # Extract style keywords (affects design decisions)
        style_keywords = []
        style_map = {
            "luxury": ["luxury", "premium", "elegant", "sophisticated", "high-end"],
            "minimalist": ["minimal", "clean", "simple", "understated"],
            "modern": ["modern", "contemporary", "sleek"],
            "playful": ["playful", "fun", "energetic", "vibrant"],
            "bold": ["bold", "striking", "dramatic"],
            "professional": ["professional", "corporate", "business"]
        }
        
        for style, keywords in style_map.items():
            if any(keyword in content_lower for keyword in keywords):
                style_keywords.append(style)
        
        if style_keywords:
            extracted["style_keywords"] = style_keywords
        
        # Extract colors (hex codes) and map to comprehensive color system
        import re
        hex_colors = re.findall(r'#[0-9A-Fa-f]{6}', content)
        
        if hex_colors:
            def color_brightness(hex_color):
                r = int(hex_color[1:3], 16)
                g = int(hex_color[3:5], 16)
                b = int(hex_color[5:7], 16)
                return r + g + b
            
            sorted_colors = sorted(hex_colors, key=color_brightness)
            
            colors = {}
            colors["primary"] = sorted_colors[0] if len(sorted_colors) >= 1 else "#1a1f3a"
            colors["secondary"] = sorted_colors[1] if len(sorted_colors) >= 2 else "#6c757d"
            colors["accent"] = sorted_colors[2] if len(sorted_colors) >= 3 else "#d4af37"
            colors["background"] = sorted_colors[-1] if len(sorted_colors) >= 4 else "#ffffff"
            colors["surface"] = "#f8f9fa"
            colors["text"] = "#2c2c2c" if color_brightness(colors["background"]) > 400 else "#f5f5f5"
            colors["text_muted"] = "#6c757d"
            colors["border"] = "#dee2e6"
            
            # Semantic colors (intelligent defaults)
            colors["success"] = "#28a745"
            colors["error"] = "#dc3545"
            colors["warning"] = "#ffc107"
            colors["info"] = "#17a2b8"
            
            extracted["colors"] = colors
        
        # Extract fonts and create typography system
        fonts_found = []
        font_keywords = {
            "Playfair Display": "playfair",
            "Cormorant": "cormorant",
            "Lato": "lato",
            "Inter": "inter",
            "Montserrat": "montserrat",
            "Roboto": "roboto",
            "Open Sans": "open sans",
            "Poppins": "poppins"
        }
        
        for font_name, keyword in font_keywords.items():
            if keyword in content_lower:
                fonts_found.append(font_name)
        
        if fonts_found:
            typography = {
                "heading_font": fonts_found[0],
                "body_font": fonts_found[1] if len(fonts_found) > 1 else fonts_found[0],
                "accent_font": fonts_found[2] if len(fonts_found) > 2 else fonts_found[0],
                "font_size_base": "16px",
                "font_size_scale": "1.25",  # Major third
                "line_height_base": "1.6",
                "line_height_heading": "1.2",
                "heading_weight": "700",
                "body_weight": "400",
                "letter_spacing": "normal"
            }
            extracted["typography"] = typography
        
        # Infer spacing system from style keywords
        if "luxury" in style_keywords or "spacious" in content_lower:
            spacing_scale = "16px"
            section_padding = "120px"
        elif "minimal" in style_keywords:
            spacing_scale = "8px"
            section_padding = "80px"
        else:
            spacing_scale = "12px"
            section_padding = "80px"
        
        extracted["spacing"] = {
            "scale": spacing_scale,
            "container_width": "1200px",
            "section_padding": section_padding,
            "card_padding": "24px",
            "grid_gap": "24px"
        }
        
        # Infer border system from style keywords
        if "modern" in style_keywords or "minimal" in style_keywords:
            borders = {
                "radius_small": "4px",
                "radius_medium": "8px",
                "radius_large": "12px",
                "width": "1px",
                "style": "solid"
            }
        elif "playful" in style_keywords:
            borders = {
                "radius_small": "8px",
                "radius_medium": "16px",
                "radius_large": "24px",
                "width": "2px",
                "style": "solid"
            }
        else:
            borders = {
                "radius_small": "6px",
                "radius_medium": "12px",
                "radius_large": "16px",
                "width": "1px",
                "style": "solid"
            }
        extracted["borders"] = borders
        
        # Shadow system based on style
        if "luxury" in style_keywords:
            shadows = {
                "small": "0 2px 4px rgba(0,0,0,0.08)",
                "medium": "0 4px 12px rgba(0,0,0,0.12)",
                "large": "0 12px 40px rgba(0,0,0,0.20)",
                "hover": "0 8px 24px rgba(0,0,0,0.15)"
            }
        elif "minimal" in style_keywords:
            shadows = {
                "small": "0 1px 2px rgba(0,0,0,0.05)",
                "medium": "0 2px 4px rgba(0,0,0,0.06)",
                "large": "0 4px 8px rgba(0,0,0,0.08)",
                "hover": "0 3px 6px rgba(0,0,0,0.08)"
            }
        else:
            shadows = {
                "small": "0 1px 3px rgba(0,0,0,0.1)",
                "medium": "0 4px 6px rgba(0,0,0,0.1)",
                "large": "0 10px 40px rgba(0,0,0,0.15)",
                "hover": "0 8px 16px rgba(0,0,0,0.12)"
            }
        extracted["shadows"] = shadows
        
        # Effects system
        extracted["effects"] = {
            "transition_speed": "200ms" if "playful" in style_keywords else "300ms",
            "transition_easing": "cubic-bezier(0.4,0,0.2,1)",
            "backdrop_blur": "8px" if "luxury" in style_keywords else "none",
            "glassmorphism": "luxury" in style_keywords
        }
        
        # Button styling
        if "minimal" in style_keywords:
            button_style = "outline"
        elif "luxury" in style_keywords:
            button_style = "solid"
        elif "modern" in style_keywords:
            button_style = "gradient"
        else:
            button_style = "solid"
        
        extracted["buttons"] = {
            "style": button_style,
            "size_padding": "12px 24px",
            "hover_effect": "lift" if "luxury" in style_keywords else "darken"
        }
        
        # Card styling
        if "minimal" in style_keywords:
            card_style = "flat"
        elif "luxury" in style_keywords:
            card_style = "elevated"
        else:
            card_style = "bordered"
        
        extracted["cards"] = {
            "style": card_style,
            "image_aspect_ratio": "3:4" if extracted["store_type"] in ["jewelry", "fashion"] else "1:1",
            "hover_effect": "lift" if "luxury" in style_keywords else "zoom-image"
        }
        
        # Layout preferences
        extracted["layout"] = {
            "header_style": "sticky",
            "product_grid_columns": "3",
            "product_grid_mobile": "1",
            "hero_height": "600px"
        }
        
        # Design preferences
        if "luxury" in style_keywords:
            whitespace = "generous"
            density = "airy"
            interaction = "subtle"
        elif "minimal" in style_keywords:
            whitespace = "balanced"
            density = "airy"
            interaction = "subtle"
        else:
            whitespace = "balanced"
            density = "standard"
            interaction = "moderate"
        
        extracted["design_preferences"] = {
            "whitespace": whitespace,
            "visual_density": density,
            "interaction_style": interaction,
            "motion_preference": "dynamic" if "playful" in style_keywords else "moderate"
        }
        
        # Extract store name if mentioned
        store_name_match = re.search(r'store[:\s]+([A-Z][a-zA-Z\s]+)', content)
        if store_name_match:
            extracted["store_name"] = store_name_match.group(1).strip()
        
        return extracted
    
    def _generate_response_message(self, extracted: Dict[str, Any]) -> str:
        """Generate AI response based on extracted info."""
        if "store_type" in extracted:
            store_type = extracted["store_type"]
            return (
                f"Great! I understand you're working with a {store_type} store. "
                f"I can create a theme that matches this perfectly. Would you like me to "
                f"generate a theme now, or would you like to provide more details?"
            )
        else:
            return (
                "I'd love to help you create a theme! Could you tell me more about "
                "your store? For example, what type of products do you sell?"
            )
    
    def _get_suggestions(
        self, 
        current_info: Dict[str, Any], 
        ready: bool
    ) -> List[str]:
        """Get contextual suggestions."""
        if ready:
            return [
                "Generate theme now",
                "Tell me more about your style preferences",
                "Upload additional brand documents"
            ]
        else:
            return [
                "My store sells jewelry",
                "I run a tech startup",
                "Upload a PRD document",
                "Tell me about style preferences"
            ]
    
    def _customize_colors(
        self, 
        base_colors: Dict[str, str], 
        requirements: Dict[str, Any]
    ) -> Dict[str, str]:
        """Customize colors based on requirements."""
        colors = base_colors.copy()
        
        # Use brand colors if provided
        if "brand_colors" in requirements and requirements["brand_colors"]:
            brand_colors = requirements["brand_colors"]
            if len(brand_colors) >= 1:
                colors["primary"] = brand_colors[0]
            if len(brand_colors) >= 2:
                colors["secondary"] = brand_colors[1]
        
        return colors
    
    def _generate_layout(self, store_type: str = "general", requirements: Dict[str, Any] = None) -> Dict[str, Any]:
        """Generate layout configuration based on store type."""
        requirements = requirements or {}
        
        # Different layouts for different store types
        layout_configs = {
            "jewelry": {
                "product_grid": {
                    "columns_desktop": 3,
                    "columns_tablet": 2,
                    "columns_mobile": 1,
                    "gap": "32px",
                    "aspect_ratio": "3:4",  # Portrait for detail
                    "style": "detailed"
                },
                "hero": {
                    "style": "full-width",
                    "height": "600px",
                    "overlay": "gradient",
                    "text_position": "center"
                },
                "navigation": {
                    "position": "top",
                    "style": "minimal",
                    "background": "transparent"
                }
            },
            "fashion": {
                "product_grid": {
                    "columns_desktop": 4,
                    "columns_tablet": 3,
                    "columns_mobile": 2,
                    "gap": "24px",
                    "aspect_ratio": "3:4",
                    "style": "hover-zoom"
                },
                "hero": {
                    "style": "split",
                    "height": "700px",
                    "overlay": "solid",
                    "text_position": "left"
                },
                "navigation": {
                    "position": "top",
                    "style": "mega-menu",
                    "background": "white"
                }
            },
            "electronics": {
                "product_grid": {
                    "columns_desktop": 4,
                    "columns_tablet": 3,
                    "columns_mobile": 2,
                    "gap": "20px",
                    "aspect_ratio": "1:1",
                    "style": "compact"
                },
                "hero": {
                    "style": "carousel",
                    "height": "500px",
                    "overlay": "none",
                    "text_position": "bottom-left"
                },
                "navigation": {
                    "position": "top",
                    "style": "with-search",
                    "background": "dark"
                }
            },
            "food": {
                "product_grid": {
                    "columns_desktop": 3,
                    "columns_tablet": 2,
                    "columns_mobile": 1,
                    "gap": "28px",
                    "aspect_ratio": "4:3",
                    "style": "menu-cards"
                },
                "hero": {
                    "style": "video-background",
                    "height": "650px",
                    "overlay": "dark",
                    "text_position": "center"
                },
                "navigation": {
                    "position": "sticky",
                    "style": "category-tabs",
                    "background": "white"
                }
            },
            "tech": {
                "product_grid": {
                    "columns_desktop": 4,
                    "columns_tablet": 3,
                    "columns_mobile": 2,
                    "gap": "20px",
                    "aspect_ratio": "16:9",
                    "style": "modern-cards"
                },
                "hero": {
                    "style": "animated",
                    "height": "550px",
                    "overlay": "gradient",
                    "text_position": "left"
                },
                "navigation": {
                    "position": "top",
                    "style": "modern",
                    "background": "gradient"
                }
            },
            "home": {
                "product_grid": {
                    "columns_desktop": 3,
                    "columns_tablet": 2,
                    "columns_mobile": 1,
                    "gap": "24px",
                    "aspect_ratio": "4:3",
                    "style": "lifestyle-cards"
                },
                "hero": {
                    "style": "lifestyle",
                    "height": "600px",
                    "overlay": "soft",
                    "text_position": "left"
                },
                "navigation": {
                    "position": "top",
                    "style": "clean",
                    "background": "white"
                }
            }
        }
        
        # Get layout for store type or use general default
        base_layout = layout_configs.get(store_type, {
            "product_grid": {
                "columns_desktop": 3,
                "columns_tablet": 2,
                "columns_mobile": 1,
                "gap": "24px",
                "aspect_ratio": "1:1",
                "style": "standard"
            },
            "hero": {
                "style": "full-width",
                "height": "500px",
                "overlay": "light",
                "text_position": "center"
            },
            "navigation": {
                "position": "top",
                "style": "standard",
                "background": "white"
            }
        })
        
        # Apply user refinements if provided
        if requirements.get("product_columns"):
            base_layout["product_grid"]["columns_desktop"] = requirements["product_columns"]
        
        if requirements.get("hero_height"):
            base_layout["hero"]["height"] = requirements["hero_height"]
        
        # Add common layout properties
        base_layout.update({
            "container_width": "1200px",
            "grid_columns": 12,
            "spacing_unit": "8px",
            "border_radius": "8px"
        })
        
        return base_layout
    
    def _generate_components(self, template: Dict[str, Any]) -> Dict[str, Any]:
        """Generate component styles."""
        return {
            "button": {
                "padding": "12px 24px",
                "border_radius": "4px",
                "font_weight": "600",
                "transition": "all 0.3s ease"
            },
            "card": {
                "padding": "24px",
                "border_radius": "8px",
                "box_shadow": "0 2px 8px rgba(0,0,0,0.1)"
            },
            "header": {
                "height": "80px",
                "padding": "0 24px"
            },
            "footer": {
                "padding": "48px 24px",
                "background": template["colors"]["background"]
            }
        }
    
    def _generate_css(
        self, 
        template: Dict[str, Any], 
        requirements: Dict[str, Any],
        store_type: str = "general"
    ) -> str:
        """Generate CSS code with layout-specific rules."""
        store_name = requirements.get("store_name", "My Store")
        layout = self._generate_layout(store_type, requirements)
        
        css = f"""/* Theme CSS for {store_name} */
/* Generated with template: {template['name']} */
/* Store Type: {store_type} */

:root {{
    --primary-color: {template['colors']['primary']};
    --secondary-color: {template['colors']['secondary']};
    --accent-color: {template['colors']['accent']};
    --background-color: {template['colors']['background']};
    --text-color: {template['colors']['text']};
    
    --heading-font: '{template['typography']['heading_font']}', serif;
    --body-font: '{template['typography']['body_font']}', sans-serif;
    
    --container-width: {layout['container_width']};
    --spacing-unit: {layout['spacing_unit']};
    --border-radius: {layout['border_radius']};
}}

* {{
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}}

body {{
    font-family: var(--body-font);
    color: var(--text-color);
    background-color: var(--background-color);
    line-height: 1.6;
}}

.container {{
    max-width: var(--container-width);
    margin: 0 auto;
    padding: 0 calc(var(--spacing-unit) * 3);
}}

h1, h2, h3, h4, h5, h6 {{
    font-family: var(--heading-font);
    font-weight: {template['typography']['heading_weight']};
    color: var(--primary-color);
    margin-bottom: calc(var(--spacing-unit) * 2);
}}

/* Hero Section - Split Layout (image and text side-by-side, no overlay) */
.hero-section {{
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0;
    min-height: {layout['hero']['height']};
    align-items: center;
}}

.hero-image {{
    width: 100%;
    height: 100%;
    min-height: {layout['hero']['height']};
    object-fit: cover;
    object-position: center;
}}

.hero-content {{
    padding: calc(var(--spacing-unit) * 6);
    background: var(--background-color);
    height: 100%;
    display: flex;
    flex-direction: column;
    justify-content: center;
}}

.hero-title {{
    font-size: 3rem;
    font-weight: {template['typography']['heading_weight']};
    margin-bottom: calc(var(--spacing-unit) * 2);
    color: var(--text-color);
}}

@media (max-width: 768px) {{
    .hero-section {{
        grid-template-columns: 1fr;
    }}
}}
    margin-bottom: calc(var(--spacing-unit) * 2);
    color: white;
}}

.hero-subtitle {{
    font-size: 1.5rem;
    margin-bottom: calc(var(--spacing-unit) * 4);
    color: rgba(255, 255, 255, 0.9);
}}

/* Navigation - GenAI Classes */
.genai-header {{
    background: var(--primary-color);
    color: white;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}}

.genai-nav {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: calc(var(--spacing-unit) * 2);
    max-width: var(--container-width);
    margin: 0 auto;
}}

.genai-nav-wrapper {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
}}

.genai-logo-link {{
    font-size: 1.5rem;
    font-weight: bold;
    color: white;
    text-decoration: none;
    font-family: var(--heading-font);
}}

.genai-nav-menu {{
    display: flex;
    gap: calc(var(--spacing-unit) * 4);
    list-style: none;
    margin: 0;
    padding: 0;
}}

.genai-nav-item {{
    margin: 0;
}}

.genai-nav-link {{
    color: white;
    text-decoration: none;
    font-weight: 500;
    transition: all 0.3s;
    padding: calc(var(--spacing-unit) * 0.5) calc(var(--spacing-unit));
    border-radius: 4px;
}}

.genai-nav-link:hover {{
    background: rgba(255,255,255,0.1);
    transform: translateY(-2px);
}}

/* Product Grid */
.product-grid {{
    display: grid;
    grid-template-columns: repeat({layout['product_grid']['columns_desktop']}, 1fr);
    gap: {layout['product_grid']['gap']};
    padding: calc(var(--spacing-unit) * 6) 0;
}}

.product-card {{
    background: white;
    border-radius: var(--border-radius);
    overflow: hidden;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
    transition: transform 0.3s, box-shadow 0.3s;
}}

.product-card:hover {{
    transform: translateY(-4px);
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
}}

.product-image {{
    width: 100%;
    aspect-ratio: {layout['product_grid']['aspect_ratio']};
    object-fit: cover;
    object-position: center;
}}

.product-info {{
    padding: calc(var(--spacing-unit) * 2);
}}

.product-title {{
    font-size: 1.125rem;
    margin-bottom: calc(var(--spacing-unit));
    color: var(--text-color);
}}

.product-price {{
    font-size: 1.25rem;
    color: var(--primary-color);
    font-weight: bold;
}}

/* Buttons */
.btn {{
    display: inline-block;
    padding: calc(var(--spacing-unit) * 1.5) calc(var(--spacing-unit) * 3);
    border-radius: var(--border-radius);
    font-weight: 600;
    text-decoration: none;
    transition: all 0.3s ease;
    cursor: pointer;
    border: none;
}}

.btn-primary {{
    background-color: var(--primary-color);
    color: white;
}}

.btn-primary:hover {{
    background-color: var(--secondary-color);
    transform: translateY(-2px);
}}

.btn-secondary {{
    background-color: transparent;
    color: var(--primary-color);
    border: 2px solid var(--primary-color);
}}

.btn-secondary:hover {{
    background-color: var(--primary-color);
    color: white;
}}

/* Footer - GenAI Classes */
.genai-footer {{
    background: var(--text-color);
    color: white;
    padding: calc(var(--spacing-unit) * 6) 0;
    margin-top: calc(var(--spacing-unit) * 8);
}}

.genai-footer .genai-container {{
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: calc(var(--spacing-unit) * 4);
}}

.genai-footer-section {{
    margin-bottom: calc(var(--spacing-unit) * 2);
}}

.genai-footer-heading {{
    color: white;
    font-weight: bold;
    margin-bottom: calc(var(--spacing-unit) * 2);
    font-size: 1.125rem;
}}

.genai-footer-text {{
    color: rgba(255,255,255,0.9);
    line-height: 1.6;
}}

.genai-footer-link {{
    color: rgba(255,255,255,0.8);
    text-decoration: none;
    transition: color 0.3s;
    display: block;
    margin-bottom: calc(var(--spacing-unit) * 0.5);
}}

.genai-footer-link:hover {{
    color: white;
    text-decoration: underline;
}}

.genai-footer-social {{
    color: rgba(255,255,255,0.8);
    line-height: 1.6;
}}

/* Responsive Design */
@media (max-width: 1024px) {{
    .product-grid {{
        grid-template-columns: repeat({layout['product_grid']['columns_tablet']}, 1fr);
    }}
    
    .hero-title {{
        font-size: 2.5rem;
    }}
    
    .genai-footer .genai-container {{
        grid-template-columns: repeat(2, 1fr);
    }}
}}

@media (max-width: 768px) {{
    .product-grid {{
        grid-template-columns: repeat({layout['product_grid']['columns_mobile']}, 1fr);
        gap: calc(var(--spacing-unit) * 2);
    }}
    
    .hero-section {{
        height: 400px;
    }}
    
    .hero-title {{
        font-size: 2rem;
    }}
    
    .hero-subtitle {{
        font-size: 1.125rem;
    }}
    
    .genai-nav-menu {{
        flex-direction: column;
        gap: calc(var(--spacing-unit) * 2);
    }}
    
    .genai-footer .genai-container {{
        grid-template-columns: 1fr;
    }}
}}
"""
        return css
    
    async def _simulate_processing_delay(self, seconds: float):
        """Simulate processing time."""
        import asyncio
        await asyncio.sleep(seconds)


# Global mock LLM instance - will be initialized with Pixabay in main.py
mock_llm = None

def initialize_mock_llm(pixabay_service=None):
    """Initialize the global mock LLM instance."""
    global mock_llm
    mock_llm = MockLLMService(pixabay_service=pixabay_service)
    return mock_llm

def get_mock_llm():
    """Get the initialized mock LLM instance."""
    global mock_llm
    if mock_llm is None:
        # Initialize with Pixabay service
        from app.services.pixabay_service import PixabayService
        from app.config import settings
        
        pixabay = None
        if settings.pixabay_api_key:
            pixabay = PixabayService(api_key=settings.pixabay_api_key)
        
        mock_llm = MockLLMService(pixabay_service=pixabay)
    return mock_llm
