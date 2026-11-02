import os
from typing import Dict, Any, Optional, List
from openai import AsyncOpenAI
from anthropic import AsyncAnthropic
from config import settings
import json


class LLMService:
    def __init__(self):
        self.provider = settings.llm_provider
        
        if self.provider == "openai":
            self.client = AsyncOpenAI(api_key=settings.openai_api_key)
            self.model = settings.openai_model
        elif self.provider == "anthropic":
            self.client = AsyncAnthropic(api_key=settings.anthropic_api_key)
            self.model = settings.anthropic_model
        else:
            raise ValueError(f"Unsupported LLM provider: {self.provider}")
        
        # Conversation history storage (in production, use Redis or database)
        self.conversations: Dict[str, List[Dict]] = {}
    
    async def chat(
        self,
        message: str,
        conversation_id: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Handle conversational chat with context awareness.
        """
        # Initialize or retrieve conversation history
        if conversation_id not in self.conversations:
            self.conversations[conversation_id] = []
        
        # Add system context if provided
        if context and len(self.conversations[conversation_id]) == 0:
            system_message = self._build_system_message(context)
            self.conversations[conversation_id].append({
                "role": "system",
                "content": system_message
            })
        
        # Add user message
        self.conversations[conversation_id].append({
            "role": "user",
            "content": message
        })
        
        # Get LLM response
        if self.provider == "openai":
            response = await self._openai_chat(conversation_id)
        else:
            response = await self._anthropic_chat(conversation_id)
        
        # Store assistant response
        self.conversations[conversation_id].append({
            "role": "assistant",
            "content": response
        })
        
        return {
            "message": response,
            "metadata": {
                "conversation_length": len(self.conversations[conversation_id])
            }
        }
    
    async def parse_requirements(
        self,
        document_text: str,
        conversation_id: str
    ) -> Dict[str, Any]:
        """
        Parse PRD document and extract structured requirements.
        """
        prompt = f"""
You are an expert at analyzing Product Requirement Documents (PRDs) for ecommerce stores.

Analyze the following PRD document and extract structured requirements for theme/design customization.

Document:
{document_text}

Extract and structure the following information in JSON format:
1. Theme preferences (colors, fonts, layout style)
2. Branding requirements (logo placement, brand colors, typography)
3. Page structure requirements (header, footer, product pages)
4. Special features or components needed
5. Design inspiration or reference websites
6. Target audience and brand personality
7. Any specific UI/UX requirements

Return a valid JSON object with these categories.
"""
        
        if self.provider == "openai":
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": "You are an expert design analyst. Always return valid JSON."},
                    {"role": "user", "content": prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.3
            )
            result = response.choices[0].message.content
        else:
            response = await self.client.messages.create(
                model=self.model,
                max_tokens=4096,
                messages=[
                    {"role": "user", "content": prompt}
                ],
                temperature=0.3
            )
            result = response.content[0].text
        
        try:
            return json.loads(result)
        except json.JSONDecodeError:
            # Fallback if LLM doesn't return valid JSON
            return {
                "raw_analysis": result,
                "theme_preferences": {},
                "branding": {},
                "page_structure": {}
            }
    
    async def simple_chat(self, message: str) -> str:
        """Simple chat for testing"""
        if self.provider == "openai":
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": message}],
                temperature=0.7
            )
            return response.choices[0].message.content
        else:
            response = await self.client.messages.create(
                model=self.model,
                max_tokens=1024,
                messages=[{"role": "user", "content": message}],
                temperature=0.7
            )
            return response.content[0].text
    
    async def _openai_chat(self, conversation_id: str) -> str:
        """OpenAI-specific chat implementation"""
        messages = self.conversations[conversation_id]
        
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            temperature=0.7,
            max_tokens=2000
        )
        
        return response.choices[0].message.content
    
    async def _anthropic_chat(self, conversation_id: str) -> str:
        """Anthropic-specific chat implementation"""
        messages = self.conversations[conversation_id]
        
        # Anthropic requires system message to be separate
        system_message = None
        chat_messages = []
        
        for msg in messages:
            if msg["role"] == "system":
                system_message = msg["content"]
            else:
                chat_messages.append(msg)
        
        kwargs = {
            "model": self.model,
            "max_tokens": 2000,
            "messages": chat_messages,
            "temperature": 0.7
        }
        
        if system_message:
            kwargs["system"] = system_message
        
        response = await self.client.messages.create(**kwargs)
        
        return response.content[0].text
    
    def _build_system_message(self, context: Dict[str, Any]) -> str:
        """Build system message with context"""
        return f"""
You are an expert ecommerce design assistant helping store owners customize their online store themes.

Your role is to:
1. Understand their design requirements and preferences
2. Ask clarifying questions when needed
3. Suggest design improvements based on best practices
4. Help them visualize their store design
5. Be friendly, professional, and creative

Current context:
- Tenant: {context.get('tenant_schema', 'unknown')}
- Store type: Ecommerce (Shopify-like)
- Current theme: Default theme active

Always provide specific, actionable advice and maintain a conversational tone.
"""
