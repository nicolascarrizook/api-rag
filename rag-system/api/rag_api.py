#!/usr/bin/env python3
"""
RAG API for Nutrition Bot
FastAPI service for semantic search in nutrition knowledge base + Telegram integration
"""

import os
import json
import logging
import hashlib
from typing import List, Dict, Optional
from datetime import datetime, timedelta

import uvicorn
import redis
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# Import our custom RAG indexer
import sys
sys.path.append('/app/scripts')
sys.path.append('/app/api')
from rag_indexer import NutritionRAGIndexer

# Import Telegram handler
try:
    from telegram_webhook import TelegramBot, TelegramUpdate
except ImportError:
    TelegramBot = None
    TelegramUpdate = None

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Nutrition RAG API",
    description="Semantic search API for nutrition knowledge base",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global variables
rag_indexer: Optional[NutritionRAGIndexer] = None
redis_client: Optional[redis.Redis] = None
telegram_bot: Optional[TelegramBot] = None

# Pydantic models
class SearchRequest(BaseModel):
    query: str = Field(..., min_length=1, max_length=500, description="Search query")
    n_results: int = Field(5, ge=1, le=20, description="Number of results to return")
    category_filter: Optional[str] = Field(None, description="Filter by category")
    use_cache: bool = Field(True, description="Use cached results if available")

class SearchResult(BaseModel):
    text: str
    metadata: Dict
    distance: float

class SearchResponse(BaseModel):
    results: List[SearchResult]
    cached: bool = False
    query_time: float
    total_results: int

class ContextRequest(BaseModel):
    patient_data: Dict = Field(..., description="Patient information")
    conversation_history: List[str] = Field(default=[], description="Recent conversation")
    motor_type: int = Field(..., ge=1, le=3, description="Motor type (1=nuevo, 2=control, 3=reemplazo)")
    specific_request: str = Field(..., description="Specific nutrition request")

class ContextResponse(BaseModel):
    context: str
    recommendations: List[str]
    relevant_sources: List[str]

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    components: Dict[str, bool]

# Dependency injection
def get_rag_indexer() -> NutritionRAGIndexer:
    if rag_indexer is None:
        raise HTTPException(status_code=500, detail="RAG indexer not initialized")
    return rag_indexer

def get_redis_client() -> redis.Redis:
    if redis_client is None:
        raise HTTPException(status_code=500, detail="Redis client not available")
    return redis_client

def get_telegram_bot() -> TelegramBot:
    if telegram_bot is None:
        raise HTTPException(status_code=500, detail="Telegram bot not initialized")
    return telegram_bot

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    global rag_indexer, redis_client, telegram_bot
    
    try:
        # Initialize Redis
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        redis_client = redis.from_url(redis_url, decode_responses=True)
        redis_client.ping()
        logger.info("Redis connection established")
        
        # Initialize RAG indexer
        data_path = "/app/data"
        embeddings_path = "/app/embeddings"
        openai_api_key = os.getenv("OPENAI_API_KEY")
        
        if not openai_api_key:
            raise ValueError("OPENAI_API_KEY not set")
        
        rag_indexer = NutritionRAGIndexer(data_path, embeddings_path, openai_api_key)
        logger.info("RAG indexer initialized")
        
        # Test the indexer
        stats = rag_indexer.get_stats()
        logger.info(f"Knowledge base stats: {stats}")
        
        # Initialize Telegram Bot
        telegram_token = os.getenv("TELEGRAM_BOT_TOKEN")
        if telegram_token:
            telegram_bot = TelegramBot(telegram_token, redis_client)
            logger.info("Telegram bot initialized")
        else:
            logger.warning("TELEGRAM_BOT_TOKEN not set - Telegram functionality disabled")
        
    except Exception as e:
        logger.error(f"Startup error: {e}")
        raise e

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    components = {
        "rag_indexer": rag_indexer is not None,
        "redis": redis_client is not None and redis_client.ping(),
        "openai_key": bool(os.getenv("OPENAI_API_KEY"))
    }
    
    status = "healthy" if all(components.values()) else "unhealthy"
    
    return HealthResponse(
        status=status,
        timestamp=datetime.now().isoformat(),
        components=components
    )

@app.post("/search", response_model=SearchResponse)
async def search_knowledge(
    request: SearchRequest,
    indexer: NutritionRAGIndexer = Depends(get_rag_indexer),
    redis: redis.Redis = Depends(get_redis_client)
):
    """Search nutrition knowledge base"""
    start_time = datetime.now()
    
    try:
        # Generate cache key
        cache_key = hashlib.md5(
            f"{request.query}_{request.n_results}_{request.category_filter}".encode()
        ).hexdigest()
        
        # Check cache if enabled
        cached_result = None
        if request.use_cache:
            try:
                cached_result = redis.get(f"search:{cache_key}")
                if cached_result:
                    cached_data = json.loads(cached_result)
                    logger.info(f"Cache hit for query: {request.query}")
                    return SearchResponse(
                        results=[SearchResult(**r) for r in cached_data["results"]],
                        cached=True,
                        query_time=0.0,
                        total_results=len(cached_data["results"])
                    )
            except Exception as e:
                logger.warning(f"Cache read error: {e}")
        
        # Perform search
        results = indexer.search(
            query=request.query,
            n_results=request.n_results,
            category_filter=request.category_filter
        )
        
        # Calculate query time
        query_time = (datetime.now() - start_time).total_seconds()
        
        # Format results
        search_results = [
            SearchResult(
                text=result["text"],
                metadata=result["metadata"],
                distance=result["distance"]
            )
            for result in results
        ]
        
        response = SearchResponse(
            results=search_results,
            cached=False,
            query_time=query_time,
            total_results=len(search_results)
        )
        
        # Cache results if enabled
        if request.use_cache and results:
            try:
                cache_data = {
                    "results": [r.dict() for r in search_results],
                    "timestamp": datetime.now().isoformat()
                }
                redis.setex(f"search:{cache_key}", 3600, json.dumps(cache_data))
            except Exception as e:
                logger.warning(f"Cache write error: {e}")
        
        logger.info(f"Search completed: '{request.query}' -> {len(results)} results in {query_time:.3f}s")
        return response
        
    except Exception as e:
        logger.error(f"Search error: {e}")
        raise HTTPException(status_code=500, detail=f"Search failed: {str(e)}")

@app.post("/context", response_model=ContextResponse)
async def generate_context(
    request: ContextRequest,
    indexer: NutritionRAGIndexer = Depends(get_rag_indexer)
):
    """Generate contextual information for meal plan generation"""
    try:
        # Build search queries based on motor type and patient data
        queries = []
        
        # Base query from patient data
        patient_query = f"plan alimentario {request.patient_data.get('objective', '')} {request.patient_data.get('activity_level', '')}"
        queries.append(patient_query)
        
        # Motor-specific queries
        if request.motor_type == 1:  # Nuevo paciente
            queries.extend([
                "plan alimentario nuevo paciente tres dias",
                f"desayuno almuerzo cena {request.patient_data.get('objective', 'mantener')}",
                "macronutrientes equilibrados proteina carbohidratos"
            ])
        elif request.motor_type == 2:  # Control
            queries.extend([
                "control plan alimentario ajustes",
                "seguimiento nutricion modificaciones"
            ])
        elif request.motor_type == 3:  # Reemplazo
            queries.extend([
                f"reemplazo {request.specific_request}",
                "alternativas comida equivalente"
            ])
        
        # Search for relevant information
        all_results = []
        for query in queries:
            results = indexer.search(query, n_results=3)
            all_results.extend(results)
        
        # Remove duplicates and get best results
        seen_texts = set()
        unique_results = []
        for result in all_results:
            if result["text"] not in seen_texts:
                unique_results.append(result)
                seen_texts.add(result["text"])
        
        # Sort by relevance (distance)
        unique_results.sort(key=lambda x: x["distance"])
        best_results = unique_results[:10]
        
        # Build context
        context_parts = []
        recommendations = []
        sources = set()
        
        for result in best_results:
            context_parts.append(result["text"])
            sources.add(result["metadata"]["source"])
            
            # Extract recommendations
            text = result["text"].lower()
            if "preparación:" in text or "macros:" in text:
                recommendations.append(result["text"][:200] + "...")
        
        context = "\n\n---\n\n".join(context_parts[:5])  # Top 5 results
        
        return ContextResponse(
            context=context,
            recommendations=recommendations[:5],
            relevant_sources=list(sources)
        )
        
    except Exception as e:
        logger.error(f"Context generation error: {e}")
        raise HTTPException(status_code=500, detail=f"Context generation failed: {str(e)}")

@app.get("/stats")
async def get_knowledge_stats(indexer: NutritionRAGIndexer = Depends(get_rag_indexer)):
    """Get knowledge base statistics"""
    try:
        stats = indexer.get_stats()
        return stats
    except Exception as e:
        logger.error(f"Stats error: {e}")
        raise HTTPException(status_code=500, detail=f"Stats retrieval failed: {str(e)}")

@app.post("/reindex")
async def reindex_knowledge(indexer: NutritionRAGIndexer = Depends(get_rag_indexer)):
    """Reindex the knowledge base"""
    try:
        logger.info("Starting reindexing...")
        indexer.load_and_index_files()
        stats = indexer.get_stats()
        logger.info("Reindexing completed")
        return {"status": "success", "stats": stats}
    except Exception as e:
        logger.error(f"Reindexing error: {e}")
        raise HTTPException(status_code=500, detail=f"Reindexing failed: {str(e)}")

@app.get("/categories")
async def get_categories(indexer: NutritionRAGIndexer = Depends(get_rag_indexer)):
    """Get available categories in knowledge base"""
    try:
        stats = indexer.get_stats()
        return {"categories": stats.get("categories", [])}
    except Exception as e:
        logger.error(f"Categories error: {e}")
        raise HTTPException(status_code=500, detail=f"Categories retrieval failed: {str(e)}")

# Telegram Bot Endpoints
@app.post("/telegram/webhook")
async def telegram_webhook(
    request: Request,
    bot: TelegramBot = Depends(get_telegram_bot)
):
    """Handle Telegram webhook updates"""
    try:
        # Get raw body for signature verification
        body = await request.body()
        body_str = body.decode()
        
        # Verify webhook signature if secret is set
        webhook_secret = os.getenv("TELEGRAM_WEBHOOK_SECRET")
        if webhook_secret:
            signature = request.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
            if not bot.verify_webhook_signature(body_str, signature):
                logger.warning("Invalid webhook signature")
                raise HTTPException(status_code=401, detail="Invalid signature")
        
        # Parse update
        try:
            update_data = json.loads(body_str)
            update = TelegramUpdate(**update_data)
        except Exception as e:
            logger.error(f"Error parsing Telegram update: {e}")
            raise HTTPException(status_code=400, detail="Invalid update format")
        
        # Process update
        response = bot.process_update(update)
        
        if response:
            logger.info(f"Processed Telegram update {update.update_id}")
            return {"status": "ok", "response": response}
        else:
            logger.info(f"No response needed for update {update.update_id}")
            return {"status": "ok"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Telegram webhook error: {e}")
        raise HTTPException(status_code=500, detail=f"Webhook processing failed: {str(e)}")

@app.get("/telegram/info")
async def telegram_info(bot: TelegramBot = Depends(get_telegram_bot)):
    """Get Telegram bot information"""
    try:
        import requests
        response = requests.get(f"{bot.api_url}/getMe")
        response.raise_for_status()
        return response.json()
    except Exception as e:
        logger.error(f"Error getting bot info: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get bot info: {str(e)}")

@app.post("/telegram/set-webhook")
async def set_telegram_webhook(
    webhook_url: str,
    bot: TelegramBot = Depends(get_telegram_bot)
):
    """Set Telegram webhook URL"""
    try:
        import requests
        
        payload = {
            "url": webhook_url,
            "allowed_updates": ["message"]
        }
        
        # Add secret token if configured
        webhook_secret = os.getenv("TELEGRAM_WEBHOOK_SECRET")
        if webhook_secret:
            payload["secret_token"] = webhook_secret
        
        response = requests.post(f"{bot.api_url}/setWebhook", json=payload)
        response.raise_for_status()
        
        result = response.json()
        logger.info(f"Webhook set to: {webhook_url}")
        return result
        
    except Exception as e:
        logger.error(f"Error setting webhook: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to set webhook: {str(e)}")

if __name__ == "__main__":
    # Run the server
    uvicorn.run(
        "rag_api:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )