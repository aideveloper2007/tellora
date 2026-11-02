"""
PgVectorStore - Semantic search and conversation history management using PostgreSQL pgvector.

Purpose in Enterprise Architecture:
- Store conversation history with vector embeddings for semantic search
- Retrieve relevant context for Claude prompting without hitting token limits
- Enable intelligent conversation pruning (keep recent + semantically relevant)
- Support learning from past conversations

Key Features:
- Multiple embedding providers (OpenAI, sentence-transformers, or disabled)
- Cosine similarity search for finding relevant conversations
- Automatic embedding generation for new messages
- Context retrieval with configurable limits

Embedding Options (in priority order):
1. OpenAI text-embedding-3-small (1536 dims) - Best quality, costs ~$0.0001/1K tokens
2. sentence-transformers all-MiniLM-L6-v2 (384 dims) - FREE, runs locally, good quality
3. Disabled - System works without semantic search (uses recency only)
"""

import logging
from typing import List, Dict, Any, Optional
import asyncio
from datetime import datetime, timedelta
import os

import asyncpg

# Try to import OpenAI (optional - requires API key and subscription)
try:
    from openai import AsyncOpenAI
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False

# Try to import sentence-transformers (free alternative - no API key needed)
try:
    from sentence_transformers import SentenceTransformer
    SENTENCE_TRANSFORMERS_AVAILABLE = True
except ImportError:
    SENTENCE_TRANSFORMERS_AVAILABLE = False

logger = logging.getLogger(__name__)


class PgVectorStore:
    """
    Manages conversation embeddings and semantic search using PostgreSQL pgvector.
    
    This service bridges the FastAPI backend with Rails database models,
    enabling AI-powered context retrieval for theme generation.
    """
    
    def __init__(self, database_url: str = None, openai_api_key: str = None, embedding_provider: str = "auto"):
        """
        Initialize PgVectorStore with database and embedding connections.
        
        Args:
            database_url: PostgreSQL connection string (from Rails database.yml)
            openai_api_key: OpenAI API key for embeddings (optional)
            embedding_provider: "auto", "openai", "sentence-transformers", or "disabled"
        """
        self.database_url = database_url or os.getenv(
            "DATABASE_URL",
            "postgresql://amars:password@localhost:5432/saasapplication_development"
        )
        self.openai_api_key = openai_api_key or os.getenv("OPENAI_API_KEY")
        
        # Determine which embedding provider to use
        self.embedding_provider = embedding_provider
        self.openai_client = None
        self.sentence_transformer = None
        
        if embedding_provider == "auto":
            # Auto-detect: prefer OpenAI if key available, then sentence-transformers, then disabled
            if self.openai_api_key and OPENAI_AVAILABLE:
                self._init_openai_embeddings()
            elif SENTENCE_TRANSFORMERS_AVAILABLE:
                self._init_sentence_transformers()
            else:
                logger.warning("No embedding provider available - semantic search will be disabled")
                self.embedding_provider = "disabled"
        elif embedding_provider == "openai":
            if not self.openai_api_key or not OPENAI_AVAILABLE:
                logger.error("OpenAI embeddings requested but not available")
                self.embedding_provider = "disabled"
            else:
                self._init_openai_embeddings()
        elif embedding_provider == "sentence-transformers":
            if not SENTENCE_TRANSFORMERS_AVAILABLE:
                logger.error("sentence-transformers requested but not installed")
                self.embedding_provider = "disabled"
            else:
                self._init_sentence_transformers()
        else:
            self.embedding_provider = "disabled"
            logger.info("Embeddings disabled - using recency-based context only")
        
        self.pool: Optional[asyncpg.Pool] = None
    
    def _init_openai_embeddings(self):
        """Initialize OpenAI embeddings."""
        self.openai_client = AsyncOpenAI(api_key=self.openai_api_key)
        self.embedding_provider = "openai"
        self.embedding_model = "text-embedding-3-small"
        self.embedding_dimensions = 1536
        logger.info("✅ Using OpenAI embeddings (text-embedding-3-small, 1536 dims)")
    
    def _init_sentence_transformers(self):
        """Initialize sentence-transformers (free, local)."""
        self.sentence_transformer = SentenceTransformer('all-MiniLM-L6-v2')
        self.embedding_provider = "sentence-transformers"
        self.embedding_model = "all-MiniLM-L6-v2"
        self.embedding_dimensions = 384
        logger.info("✅ Using FREE sentence-transformers (all-MiniLM-L6-v2, 384 dims) - No API key needed!")
    
    async def initialize(self):
        """Initialize database connection pool."""
        try:
            self.pool = await asyncpg.create_pool(
                self.database_url,
                min_size=2,
                max_size=10,
                command_timeout=60
            )
            logger.info("✅ PgVectorStore initialized with connection pool")
        except Exception as e:
            logger.error(f"Failed to initialize PgVectorStore: {str(e)}")
            raise
    
    async def close(self):
        """Close database connection pool."""
        if self.pool:
            await self.pool.close()
            logger.info("PgVectorStore connection pool closed")
    
    async def generate_embedding(self, text: str) -> Optional[List[float]]:
        """
        Generate vector embedding for text using configured provider.
        
        Supports:
        - OpenAI text-embedding-3-small (1536 dims, ~$0.0001/1K tokens)
        - sentence-transformers all-MiniLM-L6-v2 (384 dims, FREE)
        
        Args:
            text: Text to embed
            
        Returns:
            List of floats or None if embeddings disabled
        """
        if self.embedding_provider == "disabled":
            return None
        
        try:
            if self.embedding_provider == "openai":
                if not self.openai_client:
                    logger.warning("OpenAI embeddings not available")
                    return None
                
                response = await self.openai_client.embeddings.create(
                    model=self.embedding_model,
                    input=text
                )
                embedding = response.data[0].embedding
                logger.debug(f"Generated OpenAI embedding ({len(embedding)} dims)")
                return embedding
            
            elif self.embedding_provider == "sentence-transformers":
                if not self.sentence_transformer:
                    logger.warning("sentence-transformers not available")
                    return None
                
                # sentence-transformers is synchronous, run in executor to avoid blocking
                loop = asyncio.get_event_loop()
                embedding = await loop.run_in_executor(
                    None,
                    self.sentence_transformer.encode,
                    text
                )
                embedding_list = embedding.tolist()
                logger.debug(f"Generated sentence-transformers embedding ({len(embedding_list)} dims)")
                return embedding_list
            
            else:
                logger.warning(f"Unknown embedding provider: {self.embedding_provider}")
                return None
            
        except Exception as e:
            logger.error(f"Failed to generate embedding: {str(e)}")
            return None
    
    async def store_conversation_message(
        self,
        tenant: str,
        conversation_id: str,
        message_index: int,
        message_content: str,
        role: str,
        metadata: Dict[str, Any] = None
    ) -> bool:
        """
        Store a conversation message with its embedding.
        
        Args:
            tenant: Tenant identifier
            conversation_id: Unique conversation ID
            message_index: Message position in conversation
            message_content: The actual message text
            role: 'user', 'assistant', or 'system'
            metadata: Additional metadata (store_type, theme_id, etc.)
            
        Returns:
            True if stored successfully, False otherwise
        """
        if not self.pool:
            logger.error("Database pool not initialized")
            return False
        
        # Generate embedding
        embedding = await self.generate_embedding(message_content)
        
        try:
            async with self.pool.acquire() as conn:
                # Convert embedding to pgvector format
                embedding_str = f"[{','.join(map(str, embedding))}]" if embedding else None
                
                await conn.execute(
                    """
                    INSERT INTO conversation_embeddings 
                    (tenant, conversation_id, message_index, message_content, role, embedding, embedding_provider, embedding_dimensions, metadata, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6::vector, $7, $8, $9, NOW(), NOW())
                    """,
                    tenant,
                    conversation_id,
                    message_index,
                    message_content,
                    role,
                    embedding_str,
                    self.embedding_provider if embedding else None,
                    self.embedding_dimensions if embedding else None,
                    metadata or {}
                )
                
                logger.info(f"Stored conversation message: {tenant}/{conversation_id}[{message_index}]")
                return True
                
        except Exception as e:
            logger.error(f"Failed to store conversation message: {str(e)}")
            return False
    
    async def search_similar_conversations(
        self,
        tenant: str,
        query_text: str,
        limit: int = 5,
        similarity_threshold: float = 0.7
    ) -> List[Dict[str, Any]]:
        """
        Search for semantically similar conversations using cosine similarity.
        
        Args:
            tenant: Tenant identifier
            query_text: Search query
            limit: Maximum number of results
            similarity_threshold: Minimum similarity score (0-1)
            
        Returns:
            List of similar messages with metadata and similarity scores
        """
        if not self.pool:
            logger.error("Database pool not initialized")
            return []
        
        # Generate query embedding
        query_embedding = await self.generate_embedding(query_text)
        if not query_embedding:
            logger.warning("Could not generate query embedding")
            return []
        
        try:
            async with self.pool.acquire() as conn:
                embedding_str = f"[{','.join(map(str, query_embedding))}]"
                
                # Cosine similarity search: 1 - cosine_distance
                rows = await conn.fetch(
                    """
                    SELECT 
                        id,
                        conversation_id,
                        message_index,
                        message_content,
                        role,
                        metadata,
                        created_at,
                        1 - (embedding <=> $1::vector) as similarity
                    FROM conversation_embeddings
                    WHERE tenant = $2
                      AND embedding IS NOT NULL
                      AND 1 - (embedding <=> $1::vector) >= $3
                    ORDER BY embedding <=> $1::vector
                    LIMIT $4
                    """,
                    embedding_str,
                    tenant,
                    similarity_threshold,
                    limit
                )
                
                results = []
                for row in rows:
                    results.append({
                        "id": row["id"],
                        "conversation_id": row["conversation_id"],
                        "message_index": row["message_index"],
                        "message_content": row["message_content"],
                        "role": row["role"],
                        "metadata": row["metadata"],
                        "created_at": row["created_at"].isoformat(),
                        "similarity": float(row["similarity"])
                    })
                
                logger.info(f"Found {len(results)} similar conversations for tenant {tenant}")
                return results
                
        except Exception as e:
            logger.error(f"Failed to search similar conversations: {str(e)}")
            return []
    
    async def get_conversation_history(
        self,
        tenant: str,
        conversation_id: str
    ) -> List[Dict[str, Any]]:
        """
        Get full conversation history in chronological order.
        
        Args:
            tenant: Tenant identifier
            conversation_id: Conversation ID
            
        Returns:
            List of messages in order
        """
        if not self.pool:
            logger.error("Database pool not initialized")
            return []
        
        try:
            async with self.pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT 
                        id,
                        message_index,
                        message_content,
                        role,
                        metadata,
                        created_at
                    FROM conversation_embeddings
                    WHERE tenant = $1 AND conversation_id = $2
                    ORDER BY message_index ASC
                    """,
                    tenant,
                    conversation_id
                )
                
                history = []
                for row in rows:
                    history.append({
                        "id": row["id"],
                        "message_index": row["message_index"],
                        "message_content": row["message_content"],
                        "role": row["role"],
                        "metadata": row["metadata"],
                        "created_at": row["created_at"].isoformat()
                    })
                
                logger.info(f"Retrieved {len(history)} messages for conversation {conversation_id}")
                return history
                
        except Exception as e:
            logger.error(f"Failed to get conversation history: {str(e)}")
            return []
    
    async def get_relevant_context(
        self,
        tenant: str,
        current_message: str,
        conversation_id: str = None,
        max_messages: int = 10
    ) -> List[Dict[str, Any]]:
        """
        Get relevant context for a theme generation request.
        
        combines:
        1. Current conversation history (if exists)
        2. Semantically similar past conversations
        
        Args:
            tenant: Tenant identifier
            current_message: Current user message
            conversation_id: Current conversation ID (if exists)
            max_messages: Maximum context messages to return
            
        Returns:
            List of relevant messages for context
        """
        context = []
        
        # 1. Get current conversation history (recent messages)
        if conversation_id:
            history = await self.get_conversation_history(tenant, conversation_id)
            # Take last N messages from current conversation
            context.extend(history[-max_messages//2:])
        
        # 2. Search for similar past conversations
        similar = await self.search_similar_conversations(
            tenant=tenant,
            query_text=current_message,
            limit=max_messages//2,
            similarity_threshold=0.75
        )
        
        # Add similar conversations (excluding current conversation)
        for msg in similar:
            if msg["conversation_id"] != conversation_id:
                context.append(msg)
        
        # Sort by relevance/recency
        context.sort(key=lambda x: x.get("similarity", 0) or 0, reverse=True)
        
        return context[:max_messages]
    
    async def prune_old_conversations(
        self,
        tenant: str,
        days_to_keep: int = 90
    ) -> int:
        """
        Remove old conversation history to manage storage.
        
        Args:
            tenant: Tenant identifier
            days_to_keep: Number of days to retain
            
        Returns:
            Number of records deleted
        """
        if not self.pool:
            logger.error("Database pool not initialized")
            return 0
        
        try:
            cutoff_date = datetime.utcnow() - timedelta(days=days_to_keep)
            
            async with self.pool.acquire() as conn:
                result = await conn.execute(
                    """
                    DELETE FROM conversation_embeddings
                    WHERE tenant = $1 AND created_at < $2
                    """,
                    tenant,
                    cutoff_date
                )
                
                # Extract count from result string like "DELETE 42"
                deleted_count = int(result.split()[-1]) if result else 0
                
                logger.info(f"Pruned {deleted_count} old conversation records for tenant {tenant}")
                return deleted_count
                
        except Exception as e:
            logger.error(f"Failed to prune old conversations: {str(e)}")
            return 0


# Global instance
_pgvector_store: Optional[PgVectorStore] = None


async def initialize_pgvector_store(database_url: str = None, openai_api_key: str = None):
    """Initialize global PgVectorStore instance."""
    global _pgvector_store
    
    _pgvector_store = PgVectorStore(database_url=database_url, openai_api_key=openai_api_key)
    await _pgvector_store.initialize()
    
    logger.info("✅ Global PgVectorStore initialized")


def get_pgvector_store() -> Optional[PgVectorStore]:
    """Get global PgVectorStore instance."""
    return _pgvector_store


async def close_pgvector_store():
    """Close global PgVectorStore instance."""
    global _pgvector_store
    
    if _pgvector_store:
        await _pgvector_store.close()
        _pgvector_store = None
        logger.info("Global PgVectorStore closed")
