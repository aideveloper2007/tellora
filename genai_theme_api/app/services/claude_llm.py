"""Real Claude LLM service for theme generation."""

import asyncio
import json
import os
import random
import urllib.parse
import urllib.request
from typing import Dict, Any, List, Optional
from anthropic import Anthropic
import logging

logger = logging.getLogger(__name__)


def _response_text(response) -> str:
    """Join the text blocks of a Claude reply.

    Newer models can return non-text blocks (e.g. thinking) before the text,
    so content[0] is not always the answer.
    """
    parts = []
    for block in getattr(response, "content", None) or []:
        text = getattr(block, "text", None)
        if getattr(block, "type", "text") == "text" and text:
            parts.append(text)
    return "".join(parts)


class ClaudeLLMService:
    """Real Claude LLM service for AI-powered theme generation."""
    
    def __init__(self, pixabay_service=None):
        """Initialize Claude LLM service."""
        # Try to get API key from environment or settings
        from app.config import settings
        api_key = settings.claude_api_key or os.getenv("CLAUDE_API_KEY")
        
        if not api_key:
            raise ValueError("CLAUDE_API_KEY environment variable is required")
        
        self.client = Anthropic(api_key=api_key)
        self.conversation_history = {}
        self.pixabay_service = pixabay_service
        # Model is configurable via CLAUDE_MODEL env var (old model names are retired by Anthropic)
        self.model = os.getenv("CLAUDE_MODEL", "claude-sonnet-5-5")
        
        # Fallback models if the primary one is unavailable
        self.fallback_models = [
            "claude-sonnet-5-5",
            "claude-haiku-5-5",
        ]
    
    def _build_conversational_prompt(self) -> str:
        """Build the system prompt for conversational chat (NOT theme generation)."""
        return """You are a friendly, helpful AI assistant specializing in ecommerce theme design.

Your role: Have natural conversations with store owners to understand their needs.

Guidelines:
- Be conversational and friendly, not technical
- Ask clarifying questions to understand their store
- Extract key information: store type, products, brand personality, style preferences
- Explain design concepts in simple terms (avoid technical jargon)
- When you have enough info, let them know they can generate a theme
- NEVER output raw JSON or technical code in conversation
- Keep responses concise (2-4 sentences)

Example conversation:
User: "I run a luxury jewelry store"
You: "Wonderful! Luxury jewelry deserves an elegant, sophisticated design. Tell me more about your brand - are you more classic and timeless, or modern and bold? Do you have any color preferences, like gold tones or cooler metallics?"

Remember: You're chatting with a store owner, not a developer. Keep it simple and friendly!"""
    
    def _build_system_prompt(self) -> str:
        """Build the system prompt for Claude theme generation (JSON output)."""
        return """You are an EXPERT ecommerce theme designer with deep knowledge of color psychology, typography, modern web design, and industry-specific patterns.

Your mission: Create VISUALLY DISTINCTIVE themes that capture each store's unique personality.

DESIGN APPROACH:

1. Analyze the store requirements (type, description, target audience, personality)
2. Apply your professional design expertise to choose:
   - Colors that match the industry and brand personality
   - Typography that conveys the right tone
   - Layout density appropriate for the product type
   - CSS styles that make this theme visually unique

3. Use your training and design knowledge to infer appropriate choices:
   - Don't follow templates - think creatively about what THIS store needs
   - Consider competitive differentiation - make it stand out
   - Balance industry conventions with unique personality
   - Think about the target customer and what appeals to them

4. Generate substantial, custom CSS (100-300 lines) that makes this theme different from others:
   - Custom animations and transitions
   - Unique hover effects and micro-interactions  
   - Industry-appropriate visual style (elegant, playful, bold, minimal, etc.)
   - Responsive design with proper breakpoints

Return JSON matching this schema:
{
  "colors": {
    "primary": "#1a1f3a",     // CUSTOMIZE: Main brand color based on industry/personality
    "secondary": "#bdc3c7",   // CUSTOMIZE: Supporting color (usually lighter/neutral)
    "accent": "#d4af37",      // CUSTOMIZE: Call-to-action color (contrasting, eye-catching)
    "background": "#ffffff",  // CUSTOMIZE: Can be off-white, cream, light gray for warmth
    "text": "#2c2c2c"         // CUSTOMIZE: Must contrast well with background
  },
  "typography": {
    "heading_font": "Playfair Display",  // CUSTOMIZE: Choose based on brand personality
    "body_font": "Source Sans Pro",      // CUSTOMIZE: Pair well with heading font
    "heading_weight": "700",             // Adjust for emphasis
    "body_weight": "400"                 // Usually 400 or 300 for readability
  },
  "layout": {
    "container_width": "1200px",        // Adjust based on content density needs
    "header_height": "80px",            
    "product_grid_columns": 3,          // Adjust based on product type and visual emphasis
    "spacing_unit": "16px"              
  },
  "components": {
    "buttons": {
      "border_radius": "8px",           
      "padding": "12px 24px",           
      "hover_effect": "translateY(-2px)", // Get creative with hover effects
      "transition": "all 0.3s ease"     
    },
    "cards": {
      "border_radius": "12px",
      "shadow": "0 2px 8px rgba(0,0,0,0.1)",
      "hover_shadow": "0 8px 24px rgba(0,0,0,0.15)"
    }
  },
  "images": {
    "hero": {
      "search_term": "specific detailed search term for hero image",  // Be descriptive! System fetches from Pixabay later.
      "style": "photographic",
      "text_treatment": "gradient-overlay|text-shadow|backdrop-blur"  // Use layered approach - you won't see the actual image
    },
    "featured_products": {
      "search_term": "specific product photography search term",  // Match store type
      "count": 6
    }
  },
  "css": "/* ⭐ GENERATE 150-400 LINES OF CUSTOM CSS ⭐
  
  ⚠️ MANDATORY: You MUST generate complete CSS for ALL sections below. Missing any section = FAILURE.
  
  IMPORTANT: You won't see actual images - use UNIVERSAL techniques that work for any image:
  
  ========================================
  SECTION 1: NAVIGATION (REQUIRED)
  ========================================
  Generate CSS for these classes (MUST INCLUDE ALL):
  - .genai-header (header container with background, shadow)
  - .genai-nav (nav flexbox container with padding)
  - .genai-nav-wrapper (inner wrapper for alignment)
  - .genai-logo-link (store name/logo styling)
  - .genai-nav-menu (flex list with gap, no list-style)
  - .genai-nav-item (list items)
  - .genai-nav-link (link styles with color, font-weight)
  - .genai-nav-link:hover (hover effects: transform, color, background)
  
  ANALYZE THE STORE TYPE and apply appropriate design personality:
     
     Design Personality Spectrum:
     - ELEGANT/UPSCALE → Minimal spacing, thin borders (1-2px), subtle animations, serif/refined fonts, muted metallics
     - FUN/ENERGETIC → Bold borders (3-4px), rounded corners (15-25px), bounce/scale animations, bright colors, chunky fonts
     - PROFESSIONAL/TECH → Sharp corners (0-5px), gradients, glass effects (backdrop-blur), geometric, sans-serif
     - WARM/TRADITIONAL → Earth tones, decorative borders, classic fonts, textured backgrounds, medium spacing
     - CLEAN/MINIMAL → Maximum whitespace, barely-visible borders, thin fonts, fade transitions, neutral palette
     - BOLD/EDGY → Thick borders, high contrast, dramatic shadows, aggressive animations, statement typography
     
     Infer the personality from store description and apply matching visual language.
     Don't use templates - think about what makes THIS specific store unique!
  
  ========================================
  SECTION 2: HERO SECTION (REQUIRED)
  ========================================
  - .genai-hero (container with min-height, display flex, background)
  - .genai-hero-content (text wrapper)
  - .genai-hero h1, .genai-hero p (typography)
  - Layer gradient (5-35%) + text-shadow + backdrop-blur for robustness
  - Position text in bottom-center (most images darker there after gradient)
  - Trendy typography with creative text effects
  
  ========================================
  SECTION 3: PRODUCT CARDS (REQUIRED)
  ========================================
  - .genai-products (product grid container)
  - .genai-product-card (card with border, shadow, border-radius)
  - .genai-product-card:hover (transform, shadow effects)
  - .genai-product-card img (image sizing)
  - .genai-product-card .product-info (padding)
  
  MATCH THE VISUAL LANGUAGE TO STORE PERSONALITY:
     
     Animation & Hover Design Principles:
     - Elegant/Refined → Subtle lifts (2-4px), soft shadows (0 8px 24px), gentle zoom (scale 1.02-1.05)
     - Fun/Playful → Bounce effects (spring animations), bold scale (1.08-1.12), rotate/wiggle, colorful badges
     - Tech/Modern → 3D transforms, neon glows, geometric overlays, sharp transitions
     - Traditional/Warm → Soft fades, subtle borders, opacity changes, warm color shifts
     - Minimal/Clean → Barely-visible shadows, simple opacity (0.8-1.0), clean lines
     - Bold/Edgy → Dramatic shadows, aggressive scale/rotate, high contrast effects
     
     CREATE UNIQUE COMBINATIONS - analyze what makes sense for THIS store.
     Consider the products, target audience, and brand personality!
  
  ========================================
  SECTION 4: FOOTER (REQUIRED)
  ========================================
  Generate CSS for these classes (MUST INCLUDE ALL):
  - .genai-footer (footer container with background, padding, margin-top)
  - .genai-footer .genai-container (grid layout: 3 columns, gap)
  - .genai-footer-section (footer column styling)
  - .genai-footer-heading (section headings: color, font-weight, margin-bottom)
  - .genai-footer-text (body text: color, line-height)
  - .genai-footer-link (links: color, text-decoration, transition)
  - .genai-footer-link:hover (hover: color, underline)
  - .genai-footer-social (social section text)
  
  DESIGN FOOTER BASED ON BRAND PERSONALITY:
     
     Background & Typography Approaches:
     - Elegant → Dark sophisticated tones (charcoal, navy) with metallic text, elegant spacing, thin dividers
     - Fun → Bright gradients, playful shapes, emoji-friendly, rounded sections, casual fonts
     - Professional → Clean dark with accent colors, geometric patterns, structured layout
     - Traditional → Warm earth tones, ornate dividers, classic typography, medium density
     - Minimal → Light neutrals (white/light gray), maximum whitespace, invisible separators, thin fonts
     - Bold → High contrast combinations, thick borders, statement headings, dense information
     
     Analyze: What would a customer EXPECT from this type of store's footer?
     Make spacing, density, and visual weight match the brand personality!
     Each footer should FEEL different - not just look different!
     Consider: density, spacing, borders, typography weight, visual hierarchy
  
  ========================================
  SECTION 5: RESPONSIVE (REQUIRED)
  ========================================
  - @media (max-width: 768px) { ... mobile styles ... }
  - @media (max-width: 1024px) { ... tablet styles ... }
  - Navigation: stack menu vertically on mobile
  - Footer: single column on mobile, 2 columns on tablet
  
  Use the colors, fonts, and values defined above.
  Think: 'What makes THIS store different from competitors?'
  Make it TRENDY and MODERN!
  
  ⚠️ CRITICAL: CSS VALIDATION REQUIREMENTS ⚠️
  Your CSS will be validated. ANY blocked property will cause rejection!
  
  ABSOLUTELY FORBIDDEN (will cause validation failure):
  ❌ position (fixed, absolute, relative, sticky) - Use flexbox/grid instead
  ❌ z-index - Use flexbox 'order' property instead  
  ❌ top, right, bottom, left - Use margin/padding instead
  ❌ !important - Use proper selector specificity instead
  
  ALSO FORBIDDEN:
  ❌ Styling body, html, or Spree core selectors (#spree-header, .spree-checkout)
  ❌ data: URLs or http: URLs (only https:)
  ❌ expression(), javascript:, eval()
  
  SAFE ALTERNATIVES TO USE:
  ✅ Centering: display: flex; justify-content: center; align-items: center;
  ✅ Layering: Use flexbox 'order' property or natural document flow
  ✅ Spacing: margin, padding, gap
  ✅ Layout: display (flex, grid, block, inline-block)
  ✅ Styling: width, height, color, background, border, box-shadow, transform
  ✅ Animation: transition, @keyframes (max 20), animation
  ✅ Typography: font-family, font-size, font-weight, line-height
  
  REQUIRED CSS SECTIONS:
  
  1. NAVIGATION (.genai-header, .genai-nav):
     .genai-header { /* Header container */ }
     .genai-nav { /* Nav container */ }
     .genai-nav-wrapper { 
       /* Nav inner wrapper - MUST use flexbox with space-between or gap */
       display: flex;
       justify-content: space-between;
       align-items: center;
       gap: 2rem; /* Ensure spacing between logo and menu */
     }
     .genai-logo { /* Logo container */ }
     .genai-logo-link { /* Store name/logo */ }
     .genai-nav-menu { 
       /* Nav menu list - MUST use flexbox with gap */
       display: flex;
       list-style: none;
       gap: 1.5rem; /* Spacing between nav items */
     }
     .genai-nav-item { /* Nav list items */ }
     .genai-nav-link { /* Nav links */ }
     .genai-nav-link:hover { /* Hover effects */ }
  
  2. HERO SECTION (.genai-hero):
     .genai-hero { /* Hero container */ }
     .genai-hero-content { /* Text content */ }
     .genai-hero h1 { /* Main heading */ }
  
  3. PRODUCT GRID (.genai-products):
     .genai-product-card { /* Product cards */ }
     .genai-product-card:hover { /* Hover effects */ }
  
  4. FOOTER (.genai-footer):
     .genai-footer { /* Footer container */ }
     .genai-footer-section { /* Footer columns */ }
     .genai-footer-heading { /* Section headings */ }
     .genai-footer-link { /* Footer links */ }
     .genai-footer-link:hover { /* Link hover */ }
     .genai-footer-social { /* Social icons */ }
  
  5. RESPONSIVE (@media queries):
     @media (max-width: 768px) { /* Mobile styles */ }
     @media (max-width: 1024px) { /* Tablet styles */ }
  
  Example structure (NO position/z-index):
  .genai-nav {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem 2rem;
    background: linear-gradient(135deg, var(--primary), var(--secondary));
    backdrop-filter: blur(10px);
  }
  .genai-nav-menu {
    display: flex;
    gap: 2rem;
    list-style: none;
  }
  .genai-nav-link {
    transition: all 0.3s ease;
    text-decoration: none;
  }
  .genai-nav-link:hover {
    transform: translateY(-2px);
    color: var(--accent);
  }
  .genai-footer {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 3rem;
    padding: 4rem 2rem;
    background: linear-gradient(to bottom, var(--surface), var(--primary));
  }
  @media (max-width: 768px) {
    .genai-nav-menu { 
      flex-direction: column; 
      gap: 1rem; 
    }
    .genai-footer { 
      grid-template-columns: 1fr; 
    }
  }
  */",
  ✅ Styling: width, height, color, background, border, box-shadow
  ✅ Animation: transform, transition, @keyframes (max 20)
  ✅ Typography: font-family, font-size, font-weight, line-height
  
  Example structure:
  .product-card {
    display: grid;
    gap: 1rem;
    transition: transform 0.3s ease;
  }
  .product-card:hover {
    transform: translateY(-8px);
    box-shadow: 0 12px 40px rgba(0,0,0,0.15);
  }
  @media (max-width: 768px) {
    .product-grid { grid-template-columns: 1fr; }
  }
  */",
  "metadata": {
    "store_type": "detected from requirements",
    "style_keywords": ["adjective", "adjective"],
CRITICAL DESIGN RULES:
- ANALYZE THE STORE TYPE/DESCRIPTION and infer the appropriate design personality
- Every theme must look DIFFERENT - not just color swaps!
- Apply design principles dynamically based on brand personality - don't use rigid templates
- Visual variety is mandatory: spacing, borders, shadows, animations, typography weights must all vary
- CSS must be substantial (150-400 lines) with unique, contextual effects
- Image search terms must be specific and detailed to the business
- Think: "What visual style would make customers trust/engage with THIS specific type of store?"

DESIGN THINKING PROCESS:
1. Read store type → Understand the industry and target audience
2. Infer personality → Is it elegant? Fun? Professional? Edgy? Traditional? Modern?
3. Choose visual language → Spacing, borders, typography, colors, animations that match
4. Apply consistently → Navigation, products, footer should all express the personality
5. Add unique touches → What makes THIS store special?

Don't match keywords - understand the ESSENCE of the business and design accordingly!

Return ONLY the JSON object, no markdown, no explanations."""
    
    async def start_conversation(self, user_id: str, tenant_id: str) -> Dict[str, Any]:
        """Start a new conversation."""
        # Use same random ID format as Mock LLM for consistency
        conversation_id = f"conv_{random.randint(100000, 999999)}"
        
        self.conversation_history[conversation_id] = {
            "user_id": user_id,
            "tenant_id": tenant_id,
            "messages": [],
            "extracted_info": {}
        }
        
        greeting = """Welcome! 👋 I'm your AI theme designer. I can help you create a beautiful, professional theme for your online store.

To get started, tell me about your store:
- What type of products do you sell?
- What's your brand personality? (elegant, playful, modern, minimalist, etc.)
- Do you have any preferred colors or style inspiration?

Or just tell me your store type and I'll generate a complete theme for you!"""
        
        return {
            "conversation_id": conversation_id,
            "message": greeting,
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
        context: Dict[str, Any] = None,
        generate_theme: bool = False
    ) -> Dict[str, Any]:
        """Send a message in the conversation."""
        if conversation_id not in self.conversation_history:
            return {
                "error": "Conversation not found",
                "suggestion": "Start a new conversation first"
            }
        
        conv = self.conversation_history[conversation_id]
        conv["messages"].append({"role": "user", "content": message})
        
        # Extract information from user message
        self._extract_requirements(conversation_id, message)
        
        # Build messages for Claude
        messages = [
            {"role": msg["role"], "content": msg["content"]}
            for msg in conv["messages"]
        ]
        
        try:
            if generate_theme:
                # User wants to generate the theme
                return await self._generate_theme_from_conversation(conversation_id)
            else:
                # Continue conversation - use conversational prompt
                response = self.client.messages.create(
                    model=self.model,
                    max_tokens=1024,
                    system=self._build_conversational_prompt(),  # Use conversational prompt, not technical one
                    messages=messages
                )
                
                assistant_message = _response_text(response)
                if not assistant_message:
                    logger.warning(f"Claude reply had no text. Raw content: {getattr(response, 'content', None)!r}")
                    assistant_message = "Sorry, I didn't catch that. Could you tell me a bit more about your store?"
                conv["messages"].append({"role": "assistant", "content": assistant_message})
                
                return {
                    "message": assistant_message,
                    "conversation_id": conversation_id,
                    "extracted_info": conv.get("extracted_info", {}),
                    "suggestions": [],
                    "ready_for_generation": self._has_enough_info(conversation_id)
                }
        
        except Exception as e:
            logger.error(f"Claude API error: {str(e)}")
            return {
                "error": f"AI service error: {str(e)}",
                "message": "I'm having trouble right now. Please try again in a moment."
            }
    
    async def process_prd(
        self,
        conversation_id: str,
        file_content: str,
        file_name: str
    ) -> Dict[str, Any]:
        """Process a PRD document using Claude's understanding."""
        if conversation_id not in self.conversation_history:
            raise ValueError("Conversation not found")
        
        # Store the full PRD content for later use
        self.conversation_history[conversation_id]["prd_content"] = file_content
        self.conversation_history[conversation_id]["prd_filename"] = file_name
        
        # Log first 500 chars of PRD for debugging
        logger.info(f"PRD content preview (first 500 chars): {file_content[:500]}")
        
        # Ask Claude to analyze the PRD with COMPREHENSIVE enterprise-level structure
        analysis_prompt = f"""Analyze this Product Requirements Document (PRD) for an ecommerce store and extract ALL design system specifications.

PRD Content:
{file_content}

Extract and return a COMPREHENSIVE JSON object covering all CSS/design aspects:

{{
  "store_type": "descriptive store category (e.g., 'luxury jewelry', 'organic pet food', 'vintage books', 'handmade crafts', 'athletic wear', etc.)",
  "store_name": "extracted store name or null",
  
  "colors": {{
    "primary": "#hex",           // Main brand color (buttons, CTAs, links)
    "secondary": "#hex",         // Supporting color (headers, accents)
    "accent": "#hex",            // Call-to-action, highlights, badges
    "background": "#hex",        // Page background
    "surface": "#hex",           // Card/component backgrounds
    "text": "#hex",              // Body text
    "text_muted": "#hex",        // Secondary text, captions
    "border": "#hex",            // Borders, dividers
    "success": "#hex",           // Success states, in-stock badges
    "error": "#hex",             // Error states, out-of-stock
    "warning": "#hex",           // Warning states, low-stock
    "info": "#hex"               // Info messages, tooltips
  }},
  
  "typography": {{
    "heading_font": "Font Name",      // For h1-h6, product titles
    "body_font": "Font Name",         // For paragraphs, descriptions
    "accent_font": "Font Name",       // Optional: for special headings/CTAs
    "font_size_base": "16px",         // Base font size
    "font_size_scale": "1.25",        // Type scale ratio (1.2 = minor third, 1.25 = major third, 1.333 = perfect fourth)
    "line_height_base": "1.6",        // Body line height
    "line_height_heading": "1.2",     // Heading line height
    "heading_weight": "700|600|800",
    "body_weight": "400|300|500",
    "letter_spacing": "normal|tight|wide"
  }},
  
  "spacing": {{
    "scale": "8px|4px|16px",          // Base spacing unit
    "container_width": "1200px|1440px|1280px",
    "section_padding": "80px|120px|60px",
    "card_padding": "24px|32px|16px",
    "grid_gap": "24px|32px|16px"
  }},
  
  "borders": {{
    "radius_small": "4px|6px|8px",    // Small components
    "radius_medium": "8px|12px|16px", // Cards, buttons
    "radius_large": "16px|24px|32px", // Hero sections, modals
    "width": "1px|2px",
    "style": "solid|none"
  }},
  
  "shadows": {{
    "small": "0 1px 3px rgba(0,0,0,0.1)",     // Subtle elevation
    "medium": "0 4px 6px rgba(0,0,0,0.1)",    // Cards
    "large": "0 10px 40px rgba(0,0,0,0.15)",  // Modals, dropdowns
    "hover": "0 8px 16px rgba(0,0,0,0.12)"    // Interactive hover state
  }},
  
  "effects": {{
    "transition_speed": "200ms|300ms|150ms",
    "transition_easing": "ease|ease-in-out|cubic-bezier(0.4,0,0.2,1)",
    "backdrop_blur": "8px|12px|none",
    "glassmorphism": true|false
  }},
  
  "buttons": {{
    "style": "solid|outline|ghost|gradient",
    "size_padding": "12px 24px|16px 32px|10px 20px",
    "hover_effect": "lift|darken|scale|glow"
  }},
  
  "cards": {{
    "style": "elevated|bordered|flat|minimal",
    "image_aspect_ratio": "1:1|3:4|16:9|4:3",
    "hover_effect": "lift|zoom-image|border-glow|none"
  }},
  
  "layout": {{
    "header_style": "fixed|sticky|static|transparent",
    "product_grid_columns": "3|4|2",
    "product_grid_mobile": "1|2",
    "hero_height": "600px|500px|700px|full-viewport"
  }},
  
  "style_keywords": ["luxury", "minimalist", "modern", "playful", "bold", "elegant", "vibrant", etc],
  "target_audience": "description of target customers",
  "key_products": ["product 1", "product 2", ...],
  "brand_personality": "description of brand personality and tone",
  
  "design_preferences": {{
    "whitespace": "generous|compact|balanced",
    "visual_density": "airy|standard|dense",
    "interaction_style": "subtle|pronounced|playful",
    "motion_preference": "minimal|moderate|dynamic"
  }}
}}

CRITICAL INSTRUCTIONS:
1. **Store Type Detection**: Analyze the PRD content to determine the store category. Be specific and descriptive (e.g., "luxury jewelry boutique", "organic skincare", "vintage vinyl records", "handcrafted furniture"). Capture the essence of the business - don't limit to generic categories.

2. **Color Mapping**: If PRD specifies colors with context, map correctly. If just lists colors:
   - Darkest/richest → primary
   - Lightest → background
   - Medium contrast → accent
   - Dark neutral → text
   - Infer success (green), error (red), warning (orange), info (blue)

3. **Typography**: First font → heading_font, Second → body_font. Infer scale based on style (luxury=larger, minimal=balanced)

4. **Spacing**: Infer from style keywords (luxury=generous, dense=compact)

5. **Borders**: Sharp corners for modern/tech, rounded for friendly/approachable, very rounded for playful

6. **Effects**: Luxury/high-end = shadows+glassmorphism, Minimal = flat+no effects

7. **Buttons**: Solid for bold brands, outline for minimal, gradient for modern/tech

8. **Cards**: Elevated for luxury, bordered for traditional, flat for minimal

9. **Fill in EVERY field** - use intelligent defaults based on store_type and style_keywords if PRD doesn't specify

Return ONLY the JSON object, no explanation, no markdown."""
        
        try:
            response = self.client.messages.create(
                model=self.model,
                max_tokens=1024,
                messages=[
                    {"role": "user", "content": analysis_prompt}
                ]
            )
            
            # Parse Claude's response
            analysis_text = _response_text(response).strip()
            if analysis_text.startswith("```json"):
                analysis_text = analysis_text.split("```json")[1]
            if analysis_text.startswith("```"):
                analysis_text = analysis_text.split("```")[1]
            if analysis_text.endswith("```"):
                analysis_text = analysis_text.rsplit("```", 1)[0]
            analysis_text = analysis_text.strip()
            
            extracted = json.loads(analysis_text)
            
            # Update conversation with extracted info
            self.conversation_history[conversation_id]["extracted_info"].update(extracted)
            
            logger.info(f"Claude extracted PRD info: {extracted}")
            
            # Build user-friendly summary (no technical jargon)
            details = []
            
            # Style description
            if extracted.get("style_keywords"):
                style = ", ".join(extracted["style_keywords"][:3])
                details.append(f"a {style} style")
            
            # Typography (just font names, no technical details)
            if extracted.get("typography", {}).get("heading_font"):
                details.append(f"{extracted['typography']['heading_font']} typography")
            
            # Design preferences (user-friendly terms)
            if extracted.get("design_preferences", {}).get("whitespace"):
                spacing = extracted["design_preferences"]["whitespace"]
                details.append(f"{spacing} spacing")
            
            # Build natural message
            store_type = extracted.get("store_type", "store")
            if details:
                details_text = " with " + ", ".join(details)
            else:
                details_text = ""
            
            return {
                "message": f"Perfect! I've analyzed your PRD and understood your {store_type} vision{details_text}. Ready to generate your custom theme whenever you are!",
                "extracted_info": extracted,
                "file_name": file_name,
                "ready_for_generation": True
            }
            
        except Exception as e:
            logger.error(f"Error analyzing PRD with Claude: {str(e)}")
            # Fallback to basic extraction if Claude fails
            return {
                "message": f"Processed your PRD '{file_name}'. The document content has been saved and will be used for theme generation.",
                "extracted_info": {},
                "file_name": file_name,
                "ready_for_generation": True
            }
    
    async def generate_theme(
        self,
        store_type: str,
        requirements: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Generate a complete theme based on store type and requirements."""
        requirements = requirements or {}
        
        # Build generation prompt
        prompt = self._build_generation_prompt(store_type, requirements)
        
        # Try primary model, then fallbacks
        models_to_try = [self.model] + self.fallback_models
        last_error = None
        
        for model in models_to_try:
            try:
                logger.info(f"Attempting theme generation with model: {model}")
                response = self.client.messages.create(
                    model=model,
                    max_tokens=16000,  # themes include 150-400 lines of CSS; 4096 can cut the JSON off
                    system=self._build_system_prompt(),
                    messages=[
                        {"role": "user", "content": prompt}
                    ]
                )
                logger.info(f"✅ Successfully used model: {model}")
                break  # Success - exit loop
            except Exception as e:
                last_error = e
                error_msg = str(e)
                if "404" in error_msg or "not_found" in error_msg:
                    logger.warning(f"Model {model} not available, trying next...")
                    continue
                else:
                    # Not a model availability issue - propagate error
                    raise
        else:
            # All models failed
            logger.error(f"All models failed. Last error: {last_error}")
            raise last_error or Exception("All models unavailable")
        
        try:
            
            theme_json = _response_text(response)
            
            # Clean up response (remove markdown if present)
            theme_json = theme_json.strip()
            if theme_json.startswith("```json"):
                theme_json = theme_json.split("```json")[1]
            if theme_json.startswith("```"):
                theme_json = theme_json.split("```")[1]
            if theme_json.endswith("```"):
                theme_json = theme_json.rsplit("```", 1)[0]
            theme_json = theme_json.strip()
            
            # Parse JSON
            theme_data = json.loads(theme_json)
            
            # Fetch images if Pixabay service is available
            if self.pixabay_service and "images" in theme_data:
                theme_data = await self._fetch_images(theme_data)
            
            return theme_data
        
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse theme JSON: {str(e)}")
            logger.error(f"Response was: {theme_json}")
            return {
                "error": "Failed to generate valid theme",
                "details": str(e)
            }
        except Exception as e:
            logger.error(f"Theme generation error: {str(e)}")
            return {
                "error": f"Theme generation failed: {str(e)}"
            }
    
    def _build_generation_prompt(self, store_type: str, requirements: Dict[str, Any]) -> str:
        """Build comprehensive prompt for enterprise-level theme generation."""
        store_name = requirements.get("store_name", "My Store")
        style_keywords = requirements.get("style_keywords", [])
        colors = requirements.get("colors", {})
        typography = requirements.get("typography", {})
        spacing = requirements.get("spacing", {})
        borders = requirements.get("borders", {})
        shadows = requirements.get("shadows", {})
        effects = requirements.get("effects", {})
        buttons = requirements.get("buttons", {})
        cards = requirements.get("cards", {})
        layout = requirements.get("layout", {})
        design_prefs = requirements.get("design_preferences", {})
        target_audience = requirements.get("target_audience", "")
        brand_personality = requirements.get("brand_personality", "")
        key_products = requirements.get("key_products", [])
        
        prompt = f"""Generate a complete ecommerce theme for a {store_type} store named "{store_name}".

Store Details:
- Type: {store_type}
- Style preferences: {', '.join(style_keywords) if style_keywords else 'professional and modern'}"""
        
        # Add comprehensive color system
        if colors:
            prompt += f"\n\n🎨 REQUIRED COLOR SYSTEM (USE EXACTLY):"
            for color_name, color_value in colors.items():
                usage_map = {
                    "primary": "buttons, CTAs, links, brand elements",
                    "secondary": "headers, navigation, accents",
                    "accent": "highlights, badges, hover effects",
                    "background": "page background",
                    "surface": "cards, modals, component backgrounds",
                    "text": "body text, headings",
                    "text_muted": "captions, secondary text, placeholders",
                    "border": "borders, dividers, separators",
                    "success": "success messages, in-stock badges",
                    "error": "error states, out-of-stock, validation",
                    "warning": "warnings, low-stock alerts",
                    "info": "info messages, tooltips, help text"
                }
                usage = usage_map.get(color_name, color_name)
                prompt += f"\n  - {color_name}: {color_value} ({usage})"
        
        # Add typography system
        if typography:
            prompt += f"\n\n📝 REQUIRED TYPOGRAPHY (USE EXACTLY):"
            for key, value in typography.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add spacing system
        if spacing:
            prompt += f"\n\n📏 SPACING SYSTEM:"
            for key, value in spacing.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add border system
        if borders:
            prompt += f"\n\n🔲 BORDER SYSTEM:"
            for key, value in borders.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add shadow system
        if shadows:
            prompt += f"\n\n🌑 SHADOW SYSTEM:"
            for key, value in shadows.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add effects
        if effects:
            prompt += f"\n\n✨ EFFECTS & TRANSITIONS:"
            for key, value in effects.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add button styling
        if buttons:
            prompt += f"\n\n🔘 BUTTON STYLING:"
            for key, value in buttons.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add card styling
        if cards:
            prompt += f"\n\n🃏 CARD/PRODUCT STYLING:"
            for key, value in cards.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add layout preferences
        if layout:
            prompt += f"\n\n🏗️ LAYOUT PREFERENCES:"
            for key, value in layout.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add design preferences
        if design_prefs:
            prompt += f"\n\n🎭 DESIGN PREFERENCES:"
            for key, value in design_prefs.items():
                prompt += f"\n  - {key}: {value}"
        
        # Add context
        if target_audience:
            prompt += f"\n\n👥 Target audience: {target_audience}"
        if brand_personality:
            prompt += f"\n🎨 Brand personality: {brand_personality}"
        if key_products:
            prompt += f"\n📦 Key products: {', '.join(key_products[:5])}"
        
        prompt += """

⚠️ CRITICAL REQUIREMENTS:
1. USE ALL SPECIFIED DESIGN TOKENS EXACTLY - colors, fonts, spacing, borders, shadows
2. Generate CSS that implements the COMPLETE design system above
3. Apply the correct color to each element based on usage (primary for buttons, text_muted for captions, etc.)
4. Use the typography scale and spacing system consistently
5. Implement the specified button and card styles
6. Match the border radius values for different component sizes
7. Apply shadows for the specified elevation levels
8. Use the transition speed and easing for all interactions
9. Ensure all interactive states (hover, focus, active) use the design system
10. Match the store type and brand personality in component choices

CSS GENERATION:
- Generate 150-300 lines of custom CSS
- Use CSS custom properties (variables) for the design tokens
- Include responsive breakpoints (mobile, tablet, desktop)
- Add hover/focus states for all interactive elements
- Implement the specified animations and transitions
- Use the exact colors for semantic states (success, error, warning, info)

ACCESSIBILITY & LAYOUT REQUIREMENTS:
1. ⚠️ Hero Section Design - Overlay Layout (REQUIRED):
   
   USE OVERLAY DESIGN:
   - Full-width background image with text overlaid on top
   - Add dark gradient overlay (rgba) from bottom to ensure text readability
   - Center text content vertically and horizontally
   - Use backdrop-filter: blur() for additional contrast
   - Add text-shadow to ensure readability on any image
   
   CSS STRUCTURE:
   .genai-hero {
     display: flex;
     align-items: center;
     justify-content: center;
     min-height: 500px;
     background: linear-gradient(rgba(0,0,0,0.4), rgba(0,0,0,0.6)), var(--hero-bg);
     /* Note: background-image will be set inline in HTML */
   }
   .genai-hero-content {
     text-align: center;
     color: white;
     backdrop-filter: blur(2px);
     padding: 2rem;
   }
   .genai-hero h1 {
     text-shadow: 0 2px 8px rgba(0,0,0,0.7);
   }
   
2. ⚠️ Text Contrast: Ensure readable contrast (WCAG AA: 4.5:1 for body, 3:1 for large text)
3. ⚠️ Buttons: Must have sufficient background contrast
4. ⚠️ Responsive: On mobile, split layouts stack vertically

Return ONLY the JSON object with all required fields. No explanation, no markdown, just pure JSON."""
        
        return prompt
    
    async def _generate_theme_from_conversation(self, conversation_id: str) -> Dict[str, Any]:
        """Generate theme from conversation history with comprehensive design tokens."""
        conv = self.conversation_history[conversation_id]
        info = conv["extracted_info"]
        
        store_type = info.get("store_type", "general")
        
        # Pass ALL extracted design system tokens
        requirements = {
            "store_name": info.get("store_name", "My Store"),
            "style_keywords": info.get("style_keywords", []),
            "colors": info.get("colors", {}),
            "typography": info.get("typography", {}),
            "spacing": info.get("spacing", {}),
            "borders": info.get("borders", {}),
            "shadows": info.get("shadows", {}),
            "effects": info.get("effects", {}),
            "buttons": info.get("buttons", {}),
            "cards": info.get("cards", {}),
            "layout": info.get("layout", {}),
            "design_preferences": info.get("design_preferences", {}),
            "target_audience": info.get("target_audience", ""),
            "brand_personality": info.get("brand_personality", ""),
            "key_products": info.get("key_products", [])
        }
        
        theme_data = await self.generate_theme(store_type, requirements)
        
        return {
            "theme": theme_data,
            "message": "Theme generated! You can now preview and apply it to your store."
        }
    
    def _extract_requirements(self, conversation_id: str, message: str) -> None:
        """Extract requirements from user message using Claude AI."""
        conv = self.conversation_history[conversation_id]
        info = conv["extracted_info"]
        
        # Use Claude to extract structured information from the message
        try:
            response = self.client.messages.create(
                model=self.model,
                max_tokens=1024,
                system="You are an expert at extracting structured information from natural language. Extract store details, style preferences, and requirements.",
                messages=[
                    {
                        "role": "user",
                        "content": f"""Extract store information from this message: "{message}"

Return a JSON object with these fields (include only what you can determine):
{{
  "store_type": "descriptive store category (e.g., 'luxury jewelry', 'organic pet supplies', 'vintage clothing')",
  "store_name": "store name if mentioned",
  "style_keywords": ["modern", "elegant", etc],
  "products": ["list of products mentioned"],
  "target_audience": "description of customers",
  "brand_personality": "description of brand tone"
}}

Return only the JSON object, no explanation."""
                    }
                ]
            )
            
            extracted_text = _response_text(response).strip()
            if extracted_text.startswith("```json"):
                extracted_text = extracted_text.split("```json")[1].split("```")[0]
            elif extracted_text.startswith("```"):
                extracted_text = extracted_text.split("```")[1].split("```")[0]
            
            extracted_data = json.loads(extracted_text.strip())
            
            # Merge extracted data into conversation info
            for key, value in extracted_data.items():
                if value:  # Only update if value is present
                    if key == "style_keywords" and key in info:
                        # Merge style keywords
                        info[key] = list(set(info.get(key, []) + value))
                    else:
                        info[key] = value
                        
        except Exception as e:
            logger.warning(f"Failed to extract requirements with Claude: {e}")
            # Fallback to basic keyword detection
            message_lower = message.lower()
            
            # Try to identify store type from context
            if not info.get("store_type"):
                # Look for business descriptors
                if any(word in message_lower for word in ["store", "shop", "boutique", "business"]):
                    # Extract the phrase around store/shop keywords
                    for word in ["store", "shop", "boutique", "business"]:
                        if word in message_lower:
                            idx = message_lower.find(word)
                            # Get 3 words before the keyword
                            words_before = message_lower[:idx].split()[-3:]
                            store_type = " ".join(words_before).strip()
                            if store_type:
                                info["store_type"] = store_type
                                break
            
            # Extract style keywords
            style_keywords = ["elegant", "modern", "minimalist", "playful", "luxury", "vibrant", "professional", 
                            "bold", "clean", "rustic", "vintage", "contemporary", "classic"]
            found_keywords = [kw for kw in style_keywords if kw in message_lower]
            if found_keywords:
                info["style_keywords"] = list(set(info.get("style_keywords", []) + found_keywords))
    
    def _has_enough_info(self, conversation_id: str) -> bool:
        """Check if we have enough information to generate a theme."""
        info = self.conversation_history[conversation_id]["extracted_info"]
        # Ready if we have store_type, store_name, OR style keywords
        return (
            "store_type" in info or 
            "store_name" in info or
            ("style_keywords" in info and len(info["style_keywords"]) > 0)
        )
    
    async def generate_sample_products(
        self,
        store_type: str,
        store_name: str = "My Store",
        count: int = 8,
        currency: str = "USD"
    ) -> List[Dict[str, Any]]:
        """Generate realistic sample products for a new store of the given type.

        Returns a list of dicts: name, description, price, category, image_url (may be empty).
        """
        count = max(1, min(int(count), 20))
        prompt = f"""Create {count} realistic sample products for a new online store.

Store name: {store_name}
Store type: {store_type}
Currency: {currency}

Rules:
- Products must clearly belong to a "{store_type}" store
- Realistic product names (no brand names you don't own, no trademarks)
- Description: 2-3 friendly sentences a shopper would read
- Price: realistic retail price in {currency}, as a number (no currency symbol)
- Category: short category name (use 2-4 different categories across the products)
- image_search: 2-4 word photo search term for this product

Return ONLY JSON in this shape, no markdown:
{{"products": [{{"name": "...", "description": "...", "price": 19.99, "category": "...", "image_search": "..."}}]}}"""

        response = self.client.messages.create(
            model=self.model,
            max_tokens=4000,
            messages=[{"role": "user", "content": prompt}]
        )

        text = _response_text(response).strip()
        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.rsplit("```", 1)[0]
        data = json.loads(text.strip())
        raw_products = data.get("products", []) if isinstance(data, dict) else data

        products: List[Dict[str, Any]] = []
        for item in raw_products[:count]:
            if not isinstance(item, dict) or not item.get("name"):
                continue
            try:
                price = round(float(item.get("price", 0)), 2)
            except (TypeError, ValueError):
                continue
            if price <= 0:
                continue
            products.append({
                "name": str(item["name"])[:200],
                "description": str(item.get("description", ""))[:2000],
                "price": price,
                "category": str(item.get("category") or "General")[:100],
                "image_search": str(item.get("image_search") or store_type)[:100],
                "image_url": ""
            })

        # One photo search per product (its own image_search words), so a grinder
        # gets a grinder photo, not a random photo of the store type.
        if products:
            await self._attach_product_photos(products, store_type)

        logger.info(f"Generated {len(products)} sample products for store type '{store_type}'")
        return products

    # ------------------------------------------------------------------
    # Home page plan: the AI writes words and photo searches, never CSS.
    # ------------------------------------------------------------------

    PLAN_PHOTO_SLOTS = (("hero", "vertical"), ("story", "horizontal"), ("banner", "horizontal"))
    PLAN_ICONS = ["leaf", "truck", "calendar", "pin", "shield", "gift", "star",
                  "return", "heart", "sparkle", "hand", "clock"]

    async def generate_page_plan(
        self,
        store_name: str,
        description: str,
        currency: str = "USD",
        families: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """Write the home page plan for a store and find a photo for each photo section.

        Returns {"plan": {...}, "images": {"hero": {url, user, page_url, query}, ...}}.
        """
        families = [f for f in (families or []) if isinstance(f, dict) and f.get("key")]
        if not families:
            families = [{"key": "warm_artisan", "name": "Warm Artisan", "fits": "any shop"}]
        family_keys = [str(f["key"]) for f in families]
        family_lines = "\n".join(f'- {f["key"]}: {f.get("name", "")}. Fits: {f.get("fits", "")}' for f in families)

        prompt = f"""You are the copywriter and art director for a new online shop. Write the words for its home page.

Shop name: {store_name}
What the owner told us about the shop: {description}
Currency: {currency}

Style families you can choose from (pick the one that fits the shop best):
{family_lines}

Writing rules:
- Write in the same language the owner used in the description above.
- Be specific to THIS shop and what it sells. A shopper should know what the shop sells from the hero alone.
- Short, warm, concrete sentences. Sentence case, not Title Case. No exclamation marks.
- Never use these words or ideas: elevate, curated, discover our amazing, unleash, journey, seamless, world-class, premium quality, one-stop shop, welcome to.
- Do not invent facts the owner did not give: no people's names, cities, years, awards, certificates, statistics, prices or delivery thresholds. Use the shop name for the signature, for example "The {store_name} team".
- Buttons: 2 to 4 words, an action ("Shop the coffee", "See the collection").
- image_query: 2 to 4 plain English words that a stock photo site would understand, describing a real photo (for example "coffee beans roasting", "handmade ceramic mugs"). No brand names, no text, no people's names.

Return ONLY this JSON, no markdown, no comments:
{{
  "family": "one of: {', '.join(family_keys)}",
  "hero": {{
    "kicker": "up to 8 words: what the shop is",
    "title": "up to 7 words, the main promise",
    "emphasis": "2 to 5 words that finish the title, shown in italics",
    "lede": "1 to 2 sentences, up to 35 words",
    "primary_cta": "button to the products",
    "secondary_cta": "button to the shop's story",
    "note_title": "up to 5 words for a small card on the photo",
    "note_text": "1 sentence for that card",
    "image_query": "photo for the hero (tall photo)"
  }},
  "promises": [
    {{"icon": "one of: {', '.join(self.PLAN_ICONS)}", "title": "up to 4 words", "text": "up to 10 words"}},
    {{"icon": "...", "title": "...", "text": "..."}},
    {{"icon": "...", "title": "...", "text": "..."}}
  ],
  "products": {{
    "title": "heading above the product grid, up to 5 words",
    "subtitle": "1 sentence",
    "link_label": "link to all products, 2 to 3 words",
    "card_cta": "button on each product card, 1 to 3 words"
  }},
  "story": {{
    "title": "up to 10 words",
    "paragraphs": ["2 to 3 sentences", "1 to 2 sentences"],
    "signature": "short sign-off",
    "image_query": "photo for the story (wide photo)"
  }},
  "steps": {{
    "title": "up to 6 words, for example how it is made or how ordering works",
    "items": [
      {{"title": "up to 3 words", "text": "up to 14 words"}},
      {{"title": "...", "text": "..."}},
      {{"title": "...", "text": "..."}},
      {{"title": "...", "text": "..."}}
    ]
  }},
  "banner": {{
    "title": "up to 7 words",
    "text": "1 to 2 sentences",
    "cta": "2 to 4 words",
    "image_query": "photo for the banner (wide photo), different from the story photo"
  }}
}}"""

        response = self._create_message(max_tokens=3000, messages=[{"role": "user", "content": prompt}])
        plan = self._parse_json(_response_text(response))
        if not isinstance(plan, dict):
            raise ValueError("The page plan was not a JSON object")

        if plan.get("family") not in family_keys:
            plan["family"] = family_keys[0]

        images: Dict[str, Any] = {}
        used_ids = set()
        for slot, orientation in self.PLAN_PHOTO_SLOTS:
            section = plan.get(slot) if isinstance(plan.get(slot), dict) else {}
            query = str(section.get("image_query") or "").strip() or str(description)[:40]
            try:
                photos = await self.search_photos(query, count=6, orientation=orientation)
            except Exception as e:
                logger.warning(f"Photo search failed for {slot} ('{query}'): {e}")
                photos = []
            pick = next((p for p in photos if p.get("id") not in used_ids), None) or (photos[0] if photos else None)
            if pick:
                used_ids.add(pick.get("id"))
                images[slot] = pick

        logger.info(f"Page plan for '{store_name}': family={plan['family']}, photos={list(images)}")
        return {"plan": plan, "images": images}

    async def search_photos(self, query: str, count: int = 3, orientation: str = "all") -> List[Dict[str, Any]]:
        """Search Pixabay for photos matching the exact words given.

        Tries the full query first, then shorter versions of it. Each result:
        {"id", "url", "user", "page_url", "query"}.
        """
        words = [w for w in str(query or "").split() if w][:6]
        if not words:
            return []

        attempts = []
        for size in (len(words), 3, 2):
            candidate = " ".join(words[:size])
            if candidate and candidate not in attempts:
                attempts.append(candidate)

        for attempt in attempts:
            photos = await self._pixabay_search(attempt, count, orientation)
            if photos:
                return photos
        return []

    async def _pixabay_search(self, query: str, count: int, orientation: str) -> List[Dict[str, Any]]:
        key = self._pixabay_key()
        if key:
            params = {
                "key": key,
                "q": query[:100],
                "image_type": "photo",
                "safesearch": "true",
                "order": "popular",
                "min_width": 1200,
                "per_page": max(3, min(int(count) * 2, 30)),
            }
            if orientation in ("horizontal", "vertical"):
                params["orientation"] = orientation
            url = "https://pixabay.com/api/?" + urllib.parse.urlencode(params)
            data = await asyncio.to_thread(self._get_json, url)
            hits = data.get("hits", []) if isinstance(data, dict) else []
            return [
                {
                    "id": hit.get("id"),
                    "url": hit.get("largeImageURL") or hit.get("webformatURL") or "",
                    "user": hit.get("user", ""),
                    "page_url": hit.get("pageURL", ""),
                    "query": query,
                }
                for hit in hits
                if hit.get("largeImageURL") or hit.get("webformatURL")
            ][:count]

        # No key visible here: use the existing Pixabay service with the same words
        if self.pixabay_service:
            images = await self.pixabay_service.fetch_images(store_type=query, count=count)
            return [
                {
                    "id": image.get("id") or image.get("url"),
                    "url": image.get("url", ""),
                    "user": image.get("photographer") or image.get("user", ""),
                    "page_url": image.get("page_url", ""),
                    "query": query,
                }
                for image in (images or [])
                if image.get("url")
            ]
        return []

    def _pixabay_key(self) -> str:
        """The Pixabay key, wherever the service was configured with it."""
        candidates = [os.getenv("PIXABAY_API_KEY", "")]
        try:
            from app.config import settings
            candidates += [getattr(settings, name, "") for name in ("pixabay_api_key", "PIXABAY_API_KEY", "pixabay_key")]
        except Exception:
            pass
        if self.pixabay_service:
            candidates += [getattr(self.pixabay_service, name, "") for name in ("api_key", "key", "pixabay_api_key")]
        for value in candidates:
            if isinstance(value, str) and value.strip():
                return value.strip()
            secret = getattr(value, "get_secret_value", None)
            if callable(secret) and secret():
                return secret()
        return ""

    @staticmethod
    def _get_json(url: str) -> Dict[str, Any]:
        request = urllib.request.Request(url, headers={"User-Agent": "Tellora/1.0"})
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))

    async def _attach_product_photos(self, products: List[Dict[str, Any]], store_type: str) -> None:
        """Give each product a photo found with its own image_search words."""
        async def search(product):
            try:
                return await self.search_photos(product.get("image_search") or store_type, count=5, orientation="all")
            except Exception as e:
                logger.warning(f"Photo search failed for '{product.get('name')}': {e}")
                return []

        results = await asyncio.gather(*(search(p) for p in products))
        used_ids = set()
        for product, photos in zip(products, results):
            pick = next((p for p in photos if p.get("id") not in used_ids), None) or (photos[0] if photos else None)
            if pick:
                used_ids.add(pick.get("id"))
                product["image_url"] = pick.get("url", "")

        missing = [p for p in products if not p.get("image_url")]
        if missing:
            try:
                fallback = await self.search_photos(store_type, count=len(missing) + 3)
                spare = [p for p in fallback if p.get("id") not in used_ids]
                for product, photo in zip(missing, spare):
                    product["image_url"] = photo.get("url", "")
            except Exception as e:
                logger.warning(f"Fallback product photos failed: {e}")

    def _create_message(self, **kwargs):
        """messages.create with the primary model, then the fallback models."""
        last_error = None
        for model in [self.model] + [m for m in self.fallback_models if m != self.model]:
            try:
                return self.client.messages.create(model=model, **kwargs)
            except Exception as e:
                last_error = e
                if "404" in str(e) or "not_found" in str(e):
                    logger.warning(f"Model {model} not available, trying next...")
                    continue
                raise
        raise last_error or Exception("All models unavailable")

    @staticmethod
    def _parse_json(text: str) -> Any:
        text = (text or "").strip()
        if text.startswith("```"):
            text = text.split("```", 2)[1]
            if text.startswith("json"):
                text = text[4:]
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            text = text[start:end + 1]
        return json.loads(text)

    async def _fetch_images(self, theme_data: Dict[str, Any]) -> Dict[str, Any]:
        """Fetch images from Pixabay based on theme data."""
        if not self.pixabay_service:
            return theme_data
        
        try:
            images_config = theme_data.get("images", {})
            store_type = theme_data.get("store_type", "general")
            
            # Fetch hero image
            if "hero" in images_config:
                hero_image = await self.pixabay_service.fetch_hero_image(store_type=store_type)
                if hero_image:
                    images_config["hero"]["url"] = hero_image.get("url", "")
                    images_config["hero"]["source_attribution"] = hero_image.get("attribution", "Pixabay")
            
            # Fetch product images  
            if "featured_products" in images_config:
                count = images_config["featured_products"].get("count", 6)
                product_images = await self.pixabay_service.fetch_images(
                    store_type=store_type,
                    count=count
                )
                if product_images:
                    images_config["featured_products"]["images"] = [
                        {
                            "url": img.get("url", ""),
                            "title": img.get("title", "Product"),
                            "price": "$99.99"  # Placeholder - will be from actual product data
                        }
                        for img in product_images
                    ]
            
            return theme_data
        except Exception as e:
            logger.warning(f"Failed to fetch images: {e}. Continuing without images.")
            return theme_data


# Global Claude LLM instance - will be initialized in main.py
claude_llm = None

def initialize_claude_llm(pixabay_service=None):
    """Initialize the global Claude LLM instance."""
    global claude_llm
    claude_llm = ClaudeLLMService(pixabay_service=pixabay_service)
    return claude_llm

def get_claude_llm():
    """Get the initialized Claude LLM instance."""
    global claude_llm
    if claude_llm is None:
        # Initialize without Pixabay if not done yet
        claude_llm = ClaudeLLMService(pixabay_service=None)
    return claude_llm

def get_llm_service(use_real_llm: Optional[bool] = None):
    """Get the active LLM service (Claude or mock based on settings or override).
    
    Args:
        use_real_llm: Override to use real LLM (True) or mock (False).
                     If None, uses global settings.
    """
    from app.config import settings
    
    # Determine which LLM to use
    if use_real_llm is not None:
        # Use override from request
        should_use_real = use_real_llm
    else:
        # Use global config setting
        should_use_real = settings.use_real_llm
    
    if should_use_real:
        return get_claude_llm()
    else:
        from app.services.mock_llm import get_mock_llm
        return get_mock_llm()