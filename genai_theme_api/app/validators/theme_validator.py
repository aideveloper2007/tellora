"""
ThemeValidator - Multi-layer validation pipeline for enterprise-grade quality assurance.

Purpose in Enterprise Architecture:
- Validate themes before deployment (zero tolerance for errors)
- Prevent poor quality themes from reaching merchants
- Provide actionable feedback for Claude's retry attempts
- Learn from validation patterns to improve AI prompting

Validation Layers:
1. Schema validation - JSON structure correctness
2. Color validation - WCAG contrast ratios, hex format
3. Typography validation - Font existence in Google Fonts
4. CSS validation - Valid units, syntax checking
5. Layout validation - Responsive design rules
6. Security validation - XSS/injection prevention
7. Image validation - URL format, configuration
8. Quality scoring - Overall theme quality (0-100)
"""

import logging
import re
from typing import Dict, Any, List, Tuple
import colorsys

from app.validators.css_validator import get_css_validator

logger = logging.getLogger(__name__)


# Approved Google Fonts list (most popular, well-tested)
APPROVED_GOOGLE_FONTS = [
    "Inter", "Roboto", "Open Sans", "Lato", "Montserrat",
    "Poppins", "Raleway", "Playfair Display", "Merriweather",
    "Nunito", "Oswald", "Source Sans Pro", "PT Sans", "Ubuntu"
]

# Valid CSS units
VALID_CSS_UNITS = ["px", "%", "rem", "em", "vw", "vh"]


class ValidationError:
    """Represents a single validation error."""
    
    def __init__(
        self,
        error_type: str,
        field_path: str,
        message: str,
        severity: str = "error",  # 'error', 'warning'
        details: Dict[str, Any] = None
    ):
        self.error_type = error_type
        self.field_path = field_path
        self.message = message
        self.severity = severity
        self.details = details or {}
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "error_type": self.error_type,
            "field_path": self.field_path,
            "message": self.message,
            "severity": self.severity,
            "details": self.details
        }
    
    def __repr__(self):
        return f"ValidationError({self.error_type}: {self.field_path} - {self.message})"


class ThemeValidator:
    """
    Validates theme JSON against multiple quality criteria.
    
    Returns validation results with quality score and actionable feedback
    for AI retry attempts.
    """
    
    def __init__(self):
        self.errors: List[ValidationError] = []
        self.warnings: List[ValidationError] = []
    
    def validate_theme(self, theme_data: Dict[str, Any]) -> Tuple[bool, int, List[Dict]]:
        """
        Validate theme across all layers.
        
        Args:
            theme_data: Theme JSON data
            
        Returns:
            Tuple of (is_valid, quality_score, errors_list)
        """
        self.errors = []
        self.warnings = []
        
        # Run all validation layers
        self._validate_schema(theme_data)
        self._validate_colors(theme_data.get("colors", {}))
        self._validate_typography(theme_data.get("typography", {}))
        self._validate_css_values(theme_data)
        self._validate_css_syntax(theme_data.get("css", ""))  # NEW: Validate actual CSS
        self._validate_layout(theme_data.get("layout", {}))
        self._validate_security(theme_data)
        self._validate_images(theme_data.get("images", {}))
        
        # Calculate quality score
        quality_score = self._calculate_quality_score(theme_data)
        
        # Theme is valid if no critical errors
        is_valid = len(self.errors) == 0
        
        # Combine errors and warnings
        all_issues = [e.to_dict() for e in self.errors] + [w.to_dict() for w in self.warnings]
        
        logger.info(f"Theme validation: valid={is_valid}, score={quality_score}, errors={len(self.errors)}, warnings={len(self.warnings)}")
        
        return is_valid, quality_score, all_issues
    
    def _validate_schema(self, theme_data: Dict[str, Any]):
        """Validate JSON schema structure."""
        required_fields = ["colors", "typography", "layout", "images", "css"]
        
        for field in required_fields:
            if field not in theme_data:
                self.errors.append(ValidationError(
                    error_type="schema",
                    field_path=field,
                    message=f"Missing required field: {field}",
                    severity="error"
                ))
            elif field == "css" and not theme_data.get("css"):
                self.errors.append(ValidationError(
                    error_type="schema",
                    field_path="css",
                    message="CSS field is present but empty",
                    severity="error"
                ))
        
        # Validate colors structure
        if "colors" in theme_data:
            required_colors = ["primary", "secondary", "accent", "background", "text"]
            for color in required_colors:
                if color not in theme_data["colors"]:
                    self.errors.append(ValidationError(
                        error_type="schema",
                        field_path=f"colors.{color}",
                        message=f"Missing required color: {color}",
                        severity="error"
                    ))
    
    def _validate_colors(self, colors: Dict[str, str]):
        """Validate color values and contrast ratios (WCAG AA compliance)."""
        hex_pattern = re.compile(r'^#[0-9A-Fa-f]{6}$')
        
        for color_name, color_value in colors.items():
            # Validate hex format
            if not hex_pattern.match(color_value):
                self.errors.append(ValidationError(
                    error_type="color_contrast",
                    field_path=f"colors.{color_name}",
                    message=f"Invalid hex color format: {color_value}",
                    severity="error",
                    details={"value": color_value}
                ))
        
        # Check contrast ratios (WCAG AA requires 4.5:1 for normal text)
        if "background" in colors and "text" in colors:
            bg_color = colors["background"]
            text_color = colors["text"]
            
            if hex_pattern.match(bg_color) and hex_pattern.match(text_color):
                contrast_ratio = self._calculate_contrast_ratio(bg_color, text_color)
                
                if contrast_ratio < 4.5:
                    self.errors.append(ValidationError(
                        error_type="color_contrast",
                        field_path="colors.text",
                        message=f"Insufficient contrast ratio: {contrast_ratio:.2f} (minimum 4.5:1 required for WCAG AA)",
                        severity="error",
                        details={
                            "background": bg_color,
                            "text": text_color,
                            "contrast_ratio": round(contrast_ratio, 2),
                            "minimum_required": 4.5
                        }
                    ))
    
    def _validate_typography(self, typography: Dict[str, Any]):
        """Validate font families and typography settings."""
        font_fields = ["heading", "body", "button"]
        
        for field in font_fields:
            if field in typography:
                font_family = typography[field].get("fontFamily", "")
                
                # Check if font is in approved list
                if font_family and font_family not in APPROVED_GOOGLE_FONTS:
                    self.errors.append(ValidationError(
                        error_type="font",
                        field_path=f"typography.{field}.fontFamily",
                        message=f"Font '{font_family}' not in approved Google Fonts list",
                        severity="error",
                        details={
                            "provided_font": font_family,
                            "approved_fonts": APPROVED_GOOGLE_FONTS
                        }
                    ))
                
                # Validate font size
                font_size = typography[field].get("fontSize", "")
                if font_size and not any(unit in str(font_size) for unit in VALID_CSS_UNITS):
                    self.warnings.append(ValidationError(
                        error_type="css",
                        field_path=f"typography.{field}.fontSize",
                        message=f"Font size '{font_size}' should use valid CSS units",
                        severity="warning",
                        details={"valid_units": VALID_CSS_UNITS}
                    ))
    
    def _validate_css_values(self, theme_data: Dict[str, Any]):
        """Validate CSS values (units, syntax)."""
        def check_css_value(path: str, value: Any):
            if isinstance(value, str):
                # Check for valid units in size values
                size_keywords = ["width", "height", "size", "spacing", "padding", "margin", "gap"]
                if any(keyword in path.lower() for keyword in size_keywords):
                    # Should contain a valid unit
                    if not any(unit in value for unit in VALID_CSS_UNITS):
                        # Allow unitless 0 or auto
                        if value not in ["0", "auto", "initial", "inherit"]:
                            self.warnings.append(ValidationError(
                                error_type="css",
                                field_path=path,
                                message=f"CSS value '{value}' should use valid units",
                                severity="warning"
                            ))
        
        # Recursively check all values
        self._recursive_check(theme_data, "", check_css_value)
    
    def _validate_css_syntax(self, css_string: str):
        """Validate CSS syntax using enterprise-grade CSS parser."""
        if not css_string or css_string.strip() == "":
            self.errors.append(ValidationError(
                error_type="css_syntax",
                field_path="css",
                message="CSS field is empty or missing",
                severity="error"
            ))
            return
        
        # Use dedicated CSS validator with whitelist/blacklist
        css_validator = get_css_validator()
        is_valid, css_errors, css_stats = css_validator.validate_css(css_string)
        
        # Add CSS validation errors to theme validation
        for css_error in css_errors:
            severity = "error" if css_error.get("error_type") in [
                "parse_error", "blocked_property", "protected_selector", 
                "dangerous_value", "insecure_url", "security"
            ] else "warning"
            
            if severity == "error":
                self.errors.append(ValidationError(
                    error_type=css_error["error_type"],
                    field_path="css",
                    message=css_error["message"],
                    severity="error",
                    details=css_error.get("details", {})
                ))
            else:
                self.warnings.append(ValidationError(
                    error_type=css_error["error_type"],
                    field_path="css",
                    message=css_error["message"],
                    severity="warning",
                    details=css_error.get("details", {})
                ))
        
        # Log CSS statistics
        logger.info(f"CSS validation stats: {css_stats}")
        
        # Warn if CSS is too short (should be substantial)
        if len(css_string) < 500:
            self.warnings.append(ValidationError(
                error_type="css_quality",
                field_path="css",
                message=f"CSS is too short ({len(css_string)} chars). Expected substantial styling (1000+ chars).",
                severity="warning"
            ))
    
    def _validate_layout(self, layout: Dict[str, Any]):
        """Validate layout configuration."""
        # Check for reasonable container widths
        if "containerWidth" in layout:
            width = layout["containerWidth"]
            # Should be between 960px and 1920px typically
            if "px" in str(width):
                width_value = int(width.replace("px", ""))
                if width_value < 800 or width_value > 2000:
                    self.warnings.append(ValidationError(
                        error_type="layout",
                        field_path="layout.containerWidth",
                        message=f"Container width {width} may not be optimal (recommended: 1200px-1600px)",
                        severity="warning"
                    ))
    
    def _validate_security(self, theme_data: Dict[str, Any]):
        """Validate for security issues (XSS, injection)."""
        dangerous_patterns = [
            (r'<script', "Potential XSS: script tag detected"),
            (r'javascript:', "Potential XSS: javascript: protocol"),
            (r'on\w+\s*=', "Potential XSS: inline event handler"),
            (r'eval\(', "Dangerous: eval() usage"),
        ]
        
        # Convert theme data to string for pattern matching
        theme_str = str(theme_data)
        
        for pattern, message in dangerous_patterns:
            if re.search(pattern, theme_str, re.IGNORECASE):
                self.errors.append(ValidationError(
                    error_type="security",
                    field_path="theme",
                    message=message,
                    severity="error"
                ))
    
    def _validate_images(self, images: Dict[str, Any]):
        """Validate image configuration and hero overlay."""
        if "hero" in images:
            hero = images["hero"]
            
            # Check if URL is provided
            if not hero.get("url"):
                self.warnings.append(ValidationError(
                    error_type="image",
                    field_path="images.hero.url",
                    message="Hero image URL not provided",
                    severity="warning"
                ))
            
            # CRITICAL: Check for text treatment (accessibility with good design)
            if "text_treatment" not in hero and "overlay" not in hero:
                self.warnings.append(ValidationError(
                    error_type="accessibility",
                    field_path="images.hero.text_treatment",
                    message="Hero image should specify text_treatment for readability without ruining image: gradient-overlay, text-shadow, backdrop-blur, or minimal",
                    severity="warning",
                    details={
                        "recommendation": "Use 'text_treatment': 'gradient-overlay' for subtle, modern look",
                        "alternatives": ["gradient-overlay", "text-shadow", "backdrop-blur", "minimal"]
                    }
                ))
    
    def _calculate_quality_score(self, theme_data: Dict[str, Any]) -> int:
        """
        Calculate overall quality score (0-100).
        
        Scoring:
        - Start with 100
        - Deduct 20 points per critical error
        - Deduct 1 point per warning (changed from 5 - warnings are minor issues)
        - Bonus points for good practices
        
        NOTE: Score variability between generations is EXPECTED with AI.
        Each theme generation produces unique CSS, so different validation issues
        may occur. Scores fluctuating (e.g., 60→50→80) is normal because Claude
        makes different design decisions each time. This is a feature, not a bug -
        it ensures variety and creativity rather than template-based repetition.
        """
        score = 100
        
        # Penalties
        score -= len(self.errors) * 20  # Critical errors
        score -= len(self.warnings) * 1  # Warnings (minor issues, reduced penalty)
        
        # Bonuses for good practices
        if "colors" in theme_data:
            colors = theme_data["colors"]
            # Bonus for good contrast
            if "background" in colors and "text" in colors:
                contrast = self._calculate_contrast_ratio(colors["background"], colors["text"])
                if contrast >= 7.0:  # AAA level
                    score += 5
        
        # Bonus for using approved fonts
        if "typography" in theme_data:
            all_approved = all(
                font.get("fontFamily", "") in APPROVED_GOOGLE_FONTS
                for font in theme_data["typography"].values()
                if isinstance(font, dict)
            )
            if all_approved:
                score += 5
        
        # Clamp score between 0-100
        return max(0, min(100, score))
    
    def _calculate_contrast_ratio(self, hex1: str, hex2: str) -> float:
        """Calculate WCAG contrast ratio between two hex colors."""
        try:
            # Convert hex to RGB
            rgb1 = tuple(int(hex1[i:i+2], 16) for i in (1, 3, 5))
            rgb2 = tuple(int(hex2[i:i+2], 16) for i in (1, 3, 5))
            
            # Calculate relative luminance
            def luminance(rgb):
                r, g, b = [x / 255.0 for x in rgb]
                r = r / 12.92 if r <= 0.03928 else ((r + 0.055) / 1.055) ** 2.4
                g = g / 12.92 if g <= 0.03928 else ((g + 0.055) / 1.055) ** 2.4
                b = b / 12.92 if b <= 0.03928 else ((b + 0.055) / 1.055) ** 2.4
                return 0.2126 * r + 0.7152 * g + 0.0722 * b
            
            l1 = luminance(rgb1)
            l2 = luminance(rgb2)
            
            # Contrast ratio formula
            lighter = max(l1, l2)
            darker = min(l1, l2)
            ratio = (lighter + 0.05) / (darker + 0.05)
            
            return ratio
            
        except Exception as e:
            logger.error(f"Failed to calculate contrast ratio: {str(e)}")
            return 0.0
    
    def _recursive_check(self, obj: Any, path: str, check_func):
        """Recursively traverse theme data and apply check function."""
        if isinstance(obj, dict):
            for key, value in obj.items():
                new_path = f"{path}.{key}" if path else key
                check_func(new_path, value)
                self._recursive_check(value, new_path, check_func)
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                new_path = f"{path}[{i}]"
                self._recursive_check(item, new_path, check_func)
    
    def build_feedback_for_retry(self) -> str:
        """
        Build actionable feedback for Claude's retry attempt.
        
        Converts technical validation errors into natural language
        guidance that Claude can understand and act upon.
        """
        if not self.errors and not self.warnings:
            return "Theme passed all validation checks."
        
        feedback = ["The previous theme had the following issues:\n"]
        
        # Group errors by type
        errors_by_type = {}
        for error in self.errors:
            if error.error_type not in errors_by_type:
                errors_by_type[error.error_type] = []
            errors_by_type[error.error_type].append(error)
        
        for error_type, errors in errors_by_type.items():
            feedback.append(f"\n{error_type.upper()} Issues:")
            for error in errors:
                feedback.append(f"  - {error.message}")
                
                # Add actionable guidance
                if error_type == "color_contrast":
                    feedback.append("    → Increase contrast by using darker text or lighter background")
                elif error_type == "font":
                    feedback.append(f"    → Use only these approved fonts: {', '.join(APPROVED_GOOGLE_FONTS[:5])}...")
                elif error_type == "css":
                    feedback.append(f"    → Use valid CSS units: {', '.join(VALID_CSS_UNITS)}")
                elif error_type == "security":
                    feedback.append("    → Remove any inline scripts or potentially unsafe content")
        
        feedback.append("\nPlease fix these issues in the next generation attempt.")
        return "\n".join(feedback)


# Global validator instance
_theme_validator: ThemeValidator = None


def get_theme_validator() -> ThemeValidator:
    """Get or create global ThemeValidator instance."""
    global _theme_validator
    
    if _theme_validator is None:
        _theme_validator = ThemeValidator()
    
    return _theme_validator
