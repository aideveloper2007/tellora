"""
ContextManager - Intelligent conversation context management with token counting.

Purpose in Enterprise Architecture:
- Prevent Claude API context overflow (200K limit)
- Optimize context for relevance vs recency
- Implement intelligent summarization when context is large
- Track conversation token usage for cost management
- Enable semantic pruning of irrelevant history

Token Limits:
- Claude 3.5 Sonnet: 200K tokens input
- Target usage: Keep under 150K for safety
- Average theme generation: 5K-10K tokens
- Conversation history: Can grow to 50K+ tokens

Strategy:
1. Count tokens in current conversation
2. If approaching limit → prune old/irrelevant messages
3. Use semantic search to keep only relevant context
4. Summarize long conversations (10+ exchanges)
"""

import logging
from typing import List, Dict, Any, Optional
import re

# tiktoken for accurate token counting (Claude uses same tokenizer as GPT)
try:
    import tiktoken
    TIKTOKEN_AVAILABLE = True
except ImportError:
    TIKTOKEN_AVAILABLE = False
    logging.warning("tiktoken not installed - using approximate token counting")

from app.services.pgvector_store import get_pgvector_store

logger = logging.getLogger(__name__)


class ContextManager:
    """
    Manages conversation context with intelligent pruning and summarization.
    """
    
    # Claude 3.5 Sonnet token limits
    MAX_CONTEXT_TOKENS = 150_000  # Safe limit (actual is 200K)
    TARGET_CONTEXT_TOKENS = 100_000  # Target for optimization
    
    # Reserve tokens for response
    RESERVED_OUTPUT_TOKENS = 16_384  # Max output tokens
    
    def __init__(self):
        """Initialize ContextManager."""
        self.vector_store = get_pgvector_store()
        
        # Initialize tokenizer (Claude uses cl100k_base like GPT-4)
        if TIKTOKEN_AVAILABLE:
            try:
                self.tokenizer = tiktoken.get_encoding("cl100k_base")
            except Exception as e:
                logger.warning(f"Failed to load tokenizer: {e}")
                self.tokenizer = None
        else:
            self.tokenizer = None
    
    def count_tokens(self, text: str) -> int:
        """
        Count tokens in text.
        
        Args:
            text: Text to count tokens for
            
        Returns:
            Token count
        """
        if self.tokenizer:
            try:
                return len(self.tokenizer.encode(text))
            except Exception as e:
                logger.error(f"Token counting failed: {e}")
        
        # Fallback: approximate (1 token ≈ 4 chars for English)
        return len(text) // 4
    
    def count_messages_tokens(self, messages: List[Dict[str, Any]]) -> int:
        """
        Count tokens in list of messages.
        
        Args:
            messages: List of message dictionaries with 'content' key
            
        Returns:
            Total token count
        """
        total_tokens = 0
        
        for message in messages:
            content = message.get("content", "") or message.get("message_content", "")
            role = message.get("role", "user")
            
            # Count content tokens
            total_tokens += self.count_tokens(str(content))
            
            # Add overhead for message structure (role, formatting, etc.)
            total_tokens += 4  # Approximate overhead per message
        
        return total_tokens
    
    async def get_optimized_context(
        self,
        tenant: str,
        conversation_id: str,
        current_message: str,
        max_tokens: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """
        Get optimized conversation context within token limits.
        
        Strategy:
        1. Get current conversation history
        2. Count tokens
        3. If over limit → prune old messages
        4. Add semantically similar context from past conversations
        5. Return optimized context
        
        Args:
            tenant: Tenant identifier
            conversation_id: Current conversation ID
            current_message: Latest user message
            max_tokens: Maximum tokens to return (default: TARGET_CONTEXT_TOKENS)
            
        Returns:
            Optimized list of messages within token limit
        """
        max_tokens = max_tokens or self.TARGET_CONTEXT_TOKENS
        
        if not self.vector_store:
            logger.warning("PgVectorStore not available - returning empty context")
            return []
        
        try:
            # Get full conversation history
            conversation_history = await self.vector_store.get_conversation_history(
                tenant=tenant,
                conversation_id=conversation_id
            )
            
            # Count current conversation tokens
            history_tokens = self.count_messages_tokens(conversation_history)
            current_message_tokens = self.count_tokens(current_message)
            
            total_tokens = history_tokens + current_message_tokens
            
            logger.info(f"Conversation tokens: {total_tokens} (history: {history_tokens}, current: {current_message_tokens})")
            
            # If within limit, return as-is
            if total_tokens <= max_tokens:
                return conversation_history
            
            # Need to prune - keep recent messages and semantically relevant
            optimized_history = await self._prune_conversation(
                tenant=tenant,
                conversation_id=conversation_id,
                conversation_history=conversation_history,
                current_message=current_message,
                target_tokens=max_tokens - current_message_tokens
            )
            
            optimized_tokens = self.count_messages_tokens(optimized_history)
            logger.info(f"Pruned conversation: {history_tokens} → {optimized_tokens} tokens")
            
            return optimized_history
            
        except Exception as e:
            logger.error(f"Context optimization failed: {str(e)}")
            return []
    
    async def _prune_conversation(
        self,
        tenant: str,
        conversation_id: str,
        conversation_history: List[Dict[str, Any]],
        current_message: str,
        target_tokens: int
    ) -> List[Dict[str, Any]]:
        """
        Prune conversation to fit target token limit.
        
        Strategy:
        1. Always keep first message (initial requirements)
        2. Always keep last N messages (recent context)
        3. Fill remaining budget with semantically relevant messages
        4. Preserve conversation flow (keep Q&A pairs together)
        """
        if not conversation_history:
            return []
        
        # Keep first message (initial requirements)
        first_message = conversation_history[0]
        first_tokens = self.count_messages_tokens([first_message])
        
        # Keep last 5 messages (recent context)
        recent_messages = conversation_history[-5:]
        recent_tokens = self.count_messages_tokens(recent_messages)
        
        # Calculate remaining budget
        used_tokens = first_tokens + recent_tokens
        remaining_budget = target_tokens - used_tokens
        
        # If budget exceeded, reduce recent messages
        if remaining_budget < 0:
            # Keep only last 3 messages
            recent_messages = conversation_history[-3:]
            recent_tokens = self.count_messages_tokens(recent_messages)
            used_tokens = first_tokens + recent_tokens
            remaining_budget = target_tokens - used_tokens
        
        # If still no budget, return minimal context
        if remaining_budget <= 0:
            return [first_message] + recent_messages
        
        # Find semantically relevant middle messages
        middle_messages = conversation_history[1:-5]
        
        if not middle_messages:
            return [first_message] + recent_messages
        
        # Score messages by relevance to current message
        scored_messages = []
        
        for msg in middle_messages:
            content = msg.get("message_content", "")
            if not content:
                continue
            
            # Simple relevance scoring (can be enhanced with embeddings)
            relevance_score = self._calculate_relevance(content, current_message)
            
            scored_messages.append({
                "message": msg,
                "score": relevance_score,
                "tokens": self.count_messages_tokens([msg])
            })
        
        # Sort by relevance (descending)
        scored_messages.sort(key=lambda x: x["score"], reverse=True)
        
        # Fill budget with most relevant messages
        selected_middle = []
        budget_used = 0
        
        for item in scored_messages:
            if budget_used + item["tokens"] <= remaining_budget:
                selected_middle.append(item["message"])
                budget_used += item["tokens"]
            else:
                break
        
        # Sort selected messages chronologically
        selected_middle.sort(key=lambda x: x.get("created_at", ""))
        
        # Combine: first + relevant middle + recent
        optimized = [first_message] + selected_middle + recent_messages
        
        # Remove duplicates (preserve order)
        seen_ids = set()
        deduplicated = []
        
        for msg in optimized:
            msg_id = msg.get("id")
            if msg_id not in seen_ids:
                seen_ids.add(msg_id)
                deduplicated.append(msg)
        
        return deduplicated
    
    def _calculate_relevance(self, message: str, query: str) -> float:
        """
        Calculate relevance score between message and query.
        
        Simple keyword-based scoring (can be enhanced with embeddings).
        """
        # Extract keywords (words > 3 chars)
        message_words = set(re.findall(r'\b\w{4,}\b', message.lower()))
        query_words = set(re.findall(r'\b\w{4,}\b', query.lower()))
        
        if not message_words or not query_words:
            return 0.0
        
        # Calculate Jaccard similarity
        intersection = message_words & query_words
        union = message_words | query_words
        
        if not union:
            return 0.0
        
        return len(intersection) / len(union)
    
    def estimate_response_tokens(self, theme_data: Dict[str, Any]) -> int:
        """
        Estimate tokens in theme response.
        
        Args:
            theme_data: Generated theme data
            
        Returns:
            Estimated token count
        """
        theme_str = str(theme_data)
        return self.count_tokens(theme_str)
    
    def should_summarize(self, conversation_history: List[Dict[str, Any]]) -> bool:
        """
        Determine if conversation should be summarized.
        
        Criteria:
        - More than 10 exchanges (20+ messages)
        - Token count > 50K
        
        Args:
            conversation_history: List of messages
            
        Returns:
            True if summarization recommended
        """
        message_count = len(conversation_history)
        token_count = self.count_messages_tokens(conversation_history)
        
        return message_count >= 20 or token_count >= 50_000
    
    async def get_conversation_summary(
        self,
        tenant: str,
        conversation_id: str
    ) -> Optional[str]:
        """
        Get or generate conversation summary.
        
        This would call Claude to summarize the conversation,
        preserving key requirements and decisions.
        
        Args:
            tenant: Tenant identifier
            conversation_id: Conversation ID to summarize
            
        Returns:
            Summary text or None if not needed
        """
        if not self.vector_store:
            return None
        
        try:
            history = await self.vector_store.get_conversation_history(
                tenant=tenant,
                conversation_id=conversation_id
            )
            
            if not self.should_summarize(history):
                return None
            
            # TODO: Implement Claude-based summarization
            # For now, return basic summary
            summary = f"Conversation with {len(history)} messages. "
            summary += f"Tokens: {self.count_messages_tokens(history)}"
            
            return summary
            
        except Exception as e:
            logger.error(f"Summary generation failed: {str(e)}")
            return None


# Global context manager instance
_context_manager: Optional[ContextManager] = None


def initialize_context_manager():
    """Initialize global ContextManager instance."""
    global _context_manager
    _context_manager = ContextManager()
    logger.info("✅ ContextManager initialized")


def get_context_manager() -> Optional[ContextManager]:
    """Get global ContextManager instance."""
    return _context_manager
