from typing import Dict, Any, Optional
import json


class ThemeGenerator:
    """
    Service for generating and modifying theme configurations.
    """
    
    def __init__(self, llm_service):
        self.llm_service = llm_service
    
    async def generate_theme(
        self,
        requirements: Dict[str, Any],
        conversation_id: str
    ) -> Dict[str, Any]:
        """
        Generate a complete theme configuration based on requirements.
        """
        prompt = self._build_generation_prompt(requirements)
        
        if self.llm_service.provider == "openai":
            response = await self.llm_service.client.chat.completions.create(
                model=self.llm_service.model,
                messages=[
                    {"role": "system", "content": self._system_message()},
                    {"role": "user", "content": prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.7
            )
            result = response.choices[0].message.content
        else:
            response = await self.llm_service.client.messages.create(
                model=self.llm_service.model,
                max_tokens=4096,
                messages=[
                    {"role": "user", "content": self._system_message() + "\n\n" + prompt}
                ],
                temperature=0.7
            )
            result = response.content[0].text
        
        try:
            theme_data = json.loads(result)
        except json.JSONDecodeError:
            # Fallback theme
            theme_data = self._default_theme_structure()
        
        return {
            "theme_config": theme_data.get("theme_config", theme_data),
            "explanation": theme_data.get("explanation", "Theme generated based on your requirements."),
            "version": 1
        }
    
    async def modify_theme(
        self,
        previous_theme: Dict[str, Any],
        modification_request: str,
        requirements: Dict[str, Any],
        conversation_id: str
    ) -> Dict[str, Any]:
        """
        Modify existing theme based on user feedback.
        """
        prompt = f"""
Modify the following theme configuration based on the user's request.

Current Theme Configuration:
{json.dumps(previous_theme, indent=2)}

User's Modification Request:
{modification_request}

Original Requirements (for context):
{json.dumps(requirements, indent=2)}

Generate an updated theme configuration that incorporates the requested changes while maintaining consistency with the original requirements.

Return a JSON object with:
1. "theme_config": The complete updated theme configuration
2. "explanation": A clear explanation of what changes were made and why
3. "changes_summary": List of specific changes made
"""
        
        if self.llm_service.provider == "openai":
            response = await self.llm_service.client.chat.completions.create(
                model=self.llm_service.model,
                messages=[
                    {"role": "system", "content": self._system_message()},
                    {"role": "user", "content": prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.7
            )
            result = response.choices[0].message.content
        else:
            response = await self.llm_service.client.messages.create(
                model=self.llm_service.model,
                max_tokens=4096,
                messages=[
                    {"role": "user", "content": self._system_message() + "\n\n" + prompt}
                ],
                temperature=0.7
            )
            result = response.content[0].text
        
        try:
            theme_data = json.loads(result)
        except json.JSONDecodeError:
            theme_data = {"theme_config": previous_theme, "explanation": "Could not parse modifications."}
        
        return {
            "theme_config": theme_data.get("theme_config", previous_theme),
            "explanation": theme_data.get("explanation", "Theme modified based on your request."),
            "version": previous_theme.get("version", 1) + 1
        }
    
    def _system_message(self) -> str:
        return """
You are an expert ecommerce theme designer with deep knowledge of:
- Web design principles and best practices
- Color theory and typography
- Responsive design and accessibility
- Ecommerce user experience optimization
- Modern CSS and design systems

Your task is to generate complete, production-ready theme configurations in JSON format.
Always return valid JSON that follows the theme structure provided.
"""
    
    def _build_generation_prompt(self, requirements: Dict[str, Any]) -> str:
        return f"""
Generate a complete theme configuration for an ecommerce store based on these requirements:

{json.dumps(requirements, indent=2)}

Generate a JSON object with the following structure:
{{
  "theme_config": {{
    "colors": {{
      "primary": "#hex",
      "secondary": "#hex",
      "accent": "#hex",
      "background": "#hex",
      "surface": "#hex",
      "text": "#hex",
      "text_secondary": "#hex",
      "border": "#hex",
      "success": "#hex",
      "warning": "#hex",
      "error": "#hex"
    }},
    "typography": {{
      "font_family_heading": "Font name or stack",
      "font_family_body": "Font name or stack",
      "font_size_base": "16px",
      "font_weight_normal": "400",
      "font_weight_medium": "500",
      "font_weight_bold": "700",
      "line_height_base": "1.5",
      "heading_sizes": {{
        "h1": "2.5rem",
        "h2": "2rem",
        "h3": "1.75rem",
        "h4": "1.5rem"
      }}
    }},
    "spacing": {{
      "xs": "0.25rem",
      "sm": "0.5rem",
      "md": "1rem",
      "lg": "1.5rem",
      "xl": "2rem",
      "2xl": "3rem"
    }},
    "layout": {{
      "max_width": "1280px",
      "header_style": "default|minimal|prominent",
      "footer_style": "default|minimal|detailed",
      "product_grid_columns": 3,
      "border_radius": "0.5rem",
      "sidebar_position": "left|right|none"
    }},
    "components": {{
      "buttons": {{
        "style": "rounded|square|pill",
        "size_default": "medium",
        "hover_effect": "lift|glow|darken"
      }},
      "cards": {{
        "style": "elevated|outlined|flat",
        "border_radius": "0.5rem"
      }},
      "navigation": {{
        "style": "horizontal|mega|dropdown",
        "position": "sticky|static"
      }}
    }},
    "effects": {{
      "transitions": true,
      "animations": "subtle|prominent|none",
      "shadows": true
    }},
    "custom_css": {{
      "header": "",
      "footer": "",
      "product_page": "",
      "global": ""
    }}
  }},
  "explanation": "Detailed explanation of the design choices and how they align with requirements"
}}

Ensure all colors are valid hex codes, all sizes use valid CSS units, and the configuration is complete and production-ready.
"""
    
    def _default_theme_structure(self) -> Dict[str, Any]:
        """Default theme structure as fallback"""
        return {
            "theme_config": {
                "colors": {
                    "primary": "#3b82f6",
                    "secondary": "#64748b",
                    "accent": "#f59e0b",
                    "background": "#ffffff",
                    "surface": "#f9fafb",
                    "text": "#1f2937",
                    "text_secondary": "#6b7280",
                    "border": "#e5e7eb",
                    "success": "#10b981",
                    "warning": "#f59e0b",
                    "error": "#ef4444"
                },
                "typography": {
                    "font_family_heading": "'Inter', sans-serif",
                    "font_family_body": "'Inter', sans-serif",
                    "font_size_base": "16px",
                    "font_weight_normal": "400",
                    "font_weight_medium": "500",
                    "font_weight_bold": "700",
                    "line_height_base": "1.5",
                    "heading_sizes": {
                        "h1": "2.5rem",
                        "h2": "2rem",
                        "h3": "1.75rem",
                        "h4": "1.5rem"
                    }
                },
                "spacing": {
                    "xs": "0.25rem",
                    "sm": "0.5rem",
                    "md": "1rem",
                    "lg": "1.5rem",
                    "xl": "2rem",
                    "2xl": "3rem"
                },
                "layout": {
                    "max_width": "1280px",
                    "header_style": "default",
                    "footer_style": "default",
                    "product_grid_columns": 3,
                    "border_radius": "0.5rem",
                    "sidebar_position": "none"
                },
                "components": {
                    "buttons": {
                        "style": "rounded",
                        "size_default": "medium",
                        "hover_effect": "lift"
                    },
                    "cards": {
                        "style": "elevated",
                        "border_radius": "0.5rem"
                    },
                    "navigation": {
                        "style": "horizontal",
                        "position": "sticky"
                    }
                },
                "effects": {
                    "transitions": True,
                    "animations": "subtle",
                    "shadows": True
                },
                "custom_css": {
                    "header": "",
                    "footer": "",
                    "product_page": "",
                    "global": ""
                }
            },
            "explanation": "Default theme configuration with modern, clean design."
        }
