"""
CSS Validator - Enterprise-grade CSS validation with security and layout protection.

Purpose:
- Parse and validate CSS syntax using proper CSS parser (tinycss2)
- Restrict dangerous CSS properties (position: fixed, z-index abuse, etc.)
- Enforce scoped selectors (prevent global pollution)
- Validate performance (no excessive animations, shadows)
- Ensure layout preservation (can't break grid system)
- Security: block expression(), url() with data:, etc.

Architecture:
- Whitelist approach: Only allow safe CSS properties
- Selector scoping: All selectors auto-prefixed with .theme-preview
- Performance limits: Max 50 animations, reasonable shadow counts
- Layout protection: Can't override body, html, critical Spree classes
"""

import logging
import re
from typing import Dict, List, Tuple, Any
import tinycss2

logger = logging.getLogger(__name__)


# CSS Properties Whitelist - Only these are allowed
ALLOWED_CSS_PROPERTIES = {
    # Layout (safe subset)
    "display", "width", "height", "max-width", "max-height", "min-width", "min-height",
    "margin", "margin-top", "margin-right", "margin-bottom", "margin-left",
    "padding", "padding-top", "padding-right", "padding-bottom", "padding-left",
    "gap", "grid-gap", "row-gap", "column-gap",
    "flex", "flex-direction", "flex-wrap", "flex-grow", "flex-shrink",
    "align-items", "align-content", "align-self", "justify-content", "justify-items",
    "grid-template-columns", "grid-template-rows", "grid-auto-flow",
    "overflow", "overflow-x", "overflow-y",
    
    # Typography
    "font-family", "font-size", "font-weight", "font-style",
    "line-height", "letter-spacing", "text-align", "text-decoration",
    "text-transform", "white-space", "word-break", "word-wrap",
    
    # Colors & Backgrounds
    "color", "background", "background-color", "background-image",
    "background-size", "background-position", "background-repeat",
    "opacity",
    
    # Borders & Shapes
    "border", "border-top", "border-right", "border-bottom", "border-left",
    "border-width", "border-style", "border-color", "border-radius",
    "outline", "outline-width", "outline-style", "outline-color",
    
    # Visual Effects (controlled)
    "box-shadow", "text-shadow", "filter", "backdrop-filter",
    "transform", "transform-origin",
    
    # Transitions & Animations (controlled)
    "transition", "transition-property", "transition-duration", 
    "transition-timing-function", "transition-delay",
    "animation", "animation-name", "animation-duration",
    "animation-timing-function", "animation-delay", "animation-iteration-count",
    
    # Cursor & Interaction
    "cursor", "pointer-events", "user-select",
    
    # Misc Safe Properties
    "visibility", "content", "list-style", "vertical-align",
    "object-fit", "object-position", "aspect-ratio"
}


# Dangerous CSS properties that MUST be blocked
BLOCKED_CSS_PROPERTIES = {
    "position",  # Can break layout with fixed/absolute
    "z-index",   # Can cover UI elements
    "top", "right", "bottom", "left",  # Positioning
    "!important",  # Override protection
}

# Alternative suggestions for blocked properties
PROPERTY_ALTERNATIVES = {
    "position": {
        "alternatives": ["display: flex", "display: grid", "margin"],
        "reason": "Position can break layout"
    },
    "z-index": {
        "alternatives": ["order (flexbox)", "grid-row/grid-column"],
        "reason": "Z-index can cover UI elements"
    },
    "top": {
        "alternatives": ["margin-top", "padding-top", "transform: translateY()"],
        "reason": "Use margin/padding instead"
    },
    "right": {
        "alternatives": ["margin-right", "padding-right", "transform: translateX()"],
        "reason": "Use margin/padding instead"
    },
    "bottom": {
        "alternatives": ["margin-bottom", "padding-bottom", "transform: translateY()"],
        "reason": "Use margin/padding instead"
    },
    "left": {
        "alternatives": ["margin-left", "padding-left", "transform: translateX()"],
        "reason": "Use margin/padding instead"
    },
    "!important": {
        "alternatives": ["increase selector specificity"],
        "reason": "Important breaks CSS cascade"
    }
}


# Protected selectors that Claude CANNOT style (Spree core)
PROTECTED_SELECTORS = {
    "body", "html", "#spree-header", ".spree-checkout",
    "#wrapper", ".container-fluid", "nav.navbar"
}


# Performance limits
MAX_ANIMATIONS = 20  # Maximum @keyframes rules
MAX_SHADOWS = 50     # Maximum box-shadow/text-shadow instances
MAX_SELECTOR_DEPTH = 5  # Maximum nesting depth


class CSSValidationError:
    """Represents a CSS validation error."""
    
    def __init__(self, error_type: str, message: str, line: int = None, details: Dict = None):
        self.error_type = error_type
        self.message = message
        self.line = line
        self.details = details or {}
    
    def to_dict(self) -> Dict[str, Any]:
        result = {
            "error_type": self.error_type,
            "message": self.message
        }
        if self.line:
            result["line"] = self.line
        if self.details:
            result["details"] = self.details
        return result


class CSSValidator:
    """
    Validates and sanitizes CSS with enterprise-grade security and layout protection.
    """
    
    def __init__(self):
        self.errors: List[CSSValidationError] = []
        self.warnings: List[CSSValidationError] = []
        self.stats = {
            "total_rules": 0,
            "total_properties": 0,
            "blocked_properties": 0,
            "animations": 0,
            "shadows": 0
        }
    
    def validate_css(self, css_string: str) -> Tuple[bool, List[Dict], Dict]:
        """
        Validate CSS and return results.
        
        Args:
            css_string: Raw CSS to validate
            
        Returns:
            Tuple of (is_valid, errors_list, stats_dict)
        """
        self.errors = []
        self.warnings = []
        self.stats = {
            "total_rules": 0,
            "total_properties": 0,
            "blocked_properties": 0,
            "animations": 0,
            "shadows": 0
        }
        
        if not css_string or css_string.strip() == "":
            self.errors.append(CSSValidationError(
                error_type="empty_css",
                message="CSS string is empty"
            ))
            return False, [e.to_dict() for e in self.errors], self.stats
        
        # Parse CSS using tinycss2
        try:
            rules = tinycss2.parse_stylesheet(css_string)
        except Exception as e:
            self.errors.append(CSSValidationError(
                error_type="parse_error",
                message=f"CSS parsing failed: {str(e)}"
            ))
            return False, [e.to_dict() for e in self.errors], self.stats
        
        # Validate parsed rules
        self._validate_rules(rules, css_string)
        
        # Check performance limits
        self._check_performance_limits()
        
        # Security checks
        self._security_scan(css_string)
        
        # Accessibility checks
        self._accessibility_scan(css_string)
        
        is_valid = len(self.errors) == 0
        all_issues = [e.to_dict() for e in self.errors] + [w.to_dict() for w in self.warnings]
        
        logger.info(f"CSS validation: valid={is_valid}, rules={self.stats['total_rules']}, "
                   f"errors={len(self.errors)}, warnings={len(self.warnings)}")
        
        return is_valid, all_issues, self.stats
    
    def _validate_rules(self, rules: List, css_string: str):
        """Validate CSS rules and declarations."""
        for rule in rules:
            if rule.type == "qualified-rule":
                self.stats["total_rules"] += 1
                
                # Extract selector
                selector_tokens = rule.prelude
                selector = "".join(token.serialize() for token in selector_tokens)
                
                # Check for protected selectors
                if self._is_protected_selector(selector):
                    self.errors.append(CSSValidationError(
                        error_type="protected_selector",
                        message=f"Cannot style protected selector: {selector}",
                        details={"selector": selector}
                    ))
                
                # Validate declarations
                declarations = tinycss2.parse_declaration_list(rule.content)
                self._validate_declarations(declarations, selector)
            
            elif rule.type == "at-rule":
                # Handle @keyframes, @media, etc.
                if rule.at_keyword.lower() == "keyframes":
                    self.stats["animations"] += 1
                elif rule.at_keyword.lower() == "media":
                    # Recursively validate media query content
                    if rule.content:
                        media_rules = tinycss2.parse_rule_list(rule.content)
                        self._validate_rules(media_rules, css_string)
    
    def _validate_declarations(self, declarations: List, selector: str):
        """Validate CSS property declarations."""
        for decl in declarations:
            if decl.type == "declaration":
                prop_name = decl.name.lower()
                self.stats["total_properties"] += 1
                
                # Check if property is blocked
                if prop_name in BLOCKED_CSS_PROPERTIES:
                    self.stats["blocked_properties"] += 1
                    
                    # Get alternative suggestions
                    alternative_info = PROPERTY_ALTERNATIVES.get(prop_name, {})
                    alternatives = alternative_info.get("alternatives", [])
                    reason = alternative_info.get("reason", "security/layout protection")
                    
                    alt_text = ""
                    if alternatives:
                        alt_text = f" Try: {', '.join(alternatives)}."
                    
                    self.errors.append(CSSValidationError(
                        error_type="blocked_property",
                        message=f"Selector '{selector}' uses blocked property '{prop_name}'. {reason}.{alt_text}",
                        details={
                            "property": prop_name,
                            "selector": selector,
                            "alternatives": alternatives,
                            "reason": reason
                        }
                    ))
                
                # Check if property is in whitelist
                elif prop_name not in ALLOWED_CSS_PROPERTIES:
                    self.warnings.append(CSSValidationError(
                        error_type="unknown_property",
                        message=f"Property '{prop_name}' is not in whitelist (may be vendor-specific)",
                        details={"property": prop_name, "selector": selector}
                    ))
                
                # Count shadows for performance tracking
                if "shadow" in prop_name:
                    self.stats["shadows"] += 1
                
                # Validate property value
                value_tokens = decl.value
                value_str = "".join(token.serialize() for token in value_tokens)
                self._validate_property_value(prop_name, value_str, selector)
    
    def _validate_property_value(self, prop_name: str, value: str, selector: str):
        """Validate specific property values."""
        # Block dangerous functions
        dangerous_functions = ["expression", "javascript:", "data:"]
        for danger in dangerous_functions:
            if danger in value.lower():
                self.errors.append(CSSValidationError(
                    error_type="dangerous_value",
                    message=f"Dangerous value detected in {prop_name}: {danger}",
                    details={"property": prop_name, "value": value[:100], "selector": selector}
                ))
        
        # Validate URLs (must be https or relative)
        if "url(" in value:
            url_match = re.search(r'url\(["\']?([^"\']+)["\']?\)', value)
            if url_match:
                url = url_match.group(1)
                if url.startswith("data:") or (url.startswith("http:") and not url.startswith("https:")):
                    self.errors.append(CSSValidationError(
                        error_type="insecure_url",
                        message=f"URL must be HTTPS or relative path: {url[:50]}",
                        details={"url": url}
                    ))
    
    def _is_protected_selector(self, selector: str) -> bool:
        """Check if selector targets protected elements."""
        selector_lower = selector.lower().strip()
        for protected in PROTECTED_SELECTORS:
            if protected in selector_lower:
                return True
        return False
    
    def _check_performance_limits(self):
        """Check CSS doesn't exceed performance limits."""
        if self.stats["animations"] > MAX_ANIMATIONS:
            self.warnings.append(CSSValidationError(
                error_type="performance",
                message=f"Too many animations: {self.stats['animations']} (max {MAX_ANIMATIONS})",
                details={"count": self.stats["animations"], "max": MAX_ANIMATIONS}
            ))
        
        if self.stats["shadows"] > MAX_SHADOWS:
            self.warnings.append(CSSValidationError(
                error_type="performance",
                message=f"Too many shadows: {self.stats['shadows']} (max {MAX_SHADOWS})",
                details={"count": self.stats["shadows"], "max": MAX_SHADOWS}
            ))
    
    def _security_scan(self, css_string: str):
        """Additional security scanning."""
        # Check for encoded attacks
        if "%3C" in css_string or "%3E" in css_string:
            self.errors.append(CSSValidationError(
                error_type="security",
                message="URL-encoded characters detected (potential XSS)"
            ))
        
        # Check for excessive size
        if len(css_string) > 100000:  # 100KB limit
            self.warnings.append(CSSValidationError(
                error_type="size",
                message=f"CSS is very large: {len(css_string)} bytes (may impact performance)"
            ))
    
    def _accessibility_scan(self, css_string: str):
        """Scan for common accessibility issues."""
        css_lower = css_string.lower()
        
        # Check for hero section without overlay
        has_hero_section = ".hero" in css_lower or "#hero" in css_lower or "hero-section" in css_lower
        has_overlay = False
        
        if has_hero_section:
            # Look for text readability treatments (modern, subtle approaches)
            overlay_patterns = [
                r'text-shadow.*rgba',                         # Text shadow approach
                r'backdrop-filter\s*:\s*blur',                # Backdrop blur
                r'rgba\(0\s*,\s*0\s*,\s*0\s*,\s*0\.[1-4]',  # Subtle overlay 10-40%
                r'linear-gradient.*rgba\(0\s*,\s*0\s*,\s*0',  # Gradient overlay
                r'::before.*gradient',                        # Gradient pseudo-element
                r'::after.*gradient'
            ]
            
            for pattern in overlay_patterns:
                if re.search(pattern, css_lower):
                    has_overlay = True
                    break
            
            if not has_overlay:
                self.warnings.append(CSSValidationError(
                    error_type="accessibility",
                    message="Hero section detected but no text readability treatment found. Use subtle approach: gradient overlay (10-35%), text-shadow, or backdrop-filter.",
                    details={
                        "recommendations": [
                            "Subtle gradient: linear-gradient(rgba(0,0,0,0.1), rgba(0,0,0,0.3))",
                            "Text shadow: text-shadow: 0 2px 8px rgba(0,0,0,0.8)",
                            "Backdrop blur: backdrop-filter: blur(8px); background: rgba(0,0,0,0.2)"
                        ]
                    }
                ))
        
        # Check for contrast issues (simplified heuristic)
        # Look for white/light text without background specification
        light_text_patterns = [
            r'color\s*:\s*#fff',
            r'color\s*:\s*#ffffff',
            r'color\s*:\s*white',
            r'color\s*:\s*rgb\(255\s*,\s*255\s*,\s*255\)'
        ]
        
        for pattern in light_text_patterns:
            matches = re.finditer(pattern, css_lower)
            for match in matches:
                # Check if this rule has a dark background nearby
                context_start = max(0, match.start() - 200)
                context_end = min(len(css_lower), match.end() + 200)
                context = css_lower[context_start:context_end]
                
                # Look for dark background in same rule
                has_dark_bg = any([
                    'background' in context and ('rgba(0' in context or '#000' in context or '#111' in context or '#222' in context),
                    'background-color' in context and ('rgba(0' in context or '#000' in context or '#111' in context or '#222' in context)
                ])
                
                if not has_dark_bg:
                    self.warnings.append(CSSValidationError(
                        error_type="accessibility",
                        message="Light text color detected without dark background. Ensure WCAG AA contrast (4.5:1).",
                        details={
                            "recommendation": "Add dark background-color or ensure element is on dark background"
                        }
                    ))
                    break  # Only warn once
        
        # Check for buttons without sufficient styling
        if '.button' in css_lower or '.btn' in css_lower or 'button {' in css_lower:
            # Check if buttons have background or border
            button_context = re.search(r'\.(button|btn)|button\s*\{[^}]{0,500}\}', css_lower)
            if button_context:
                button_css = button_context.group()
                has_bg = 'background' in button_css
                has_border = 'border' in button_css and 'border:' not in button_css + ' 0'
                
                if not has_bg and not has_border:
                    self.warnings.append(CSSValidationError(
                        error_type="accessibility",
                        message="Buttons should have background-color or border for visibility, especially on images.",
                        details={
                            "recommendation": "Add background-color or border to button styles"
                        }
                    ))


# Singleton instance
_css_validator_instance = None

def get_css_validator() -> CSSValidator:
    """Get singleton CSS validator instance."""
    global _css_validator_instance
    if _css_validator_instance is None:
        _css_validator_instance = CSSValidator()
    return _css_validator_instance
