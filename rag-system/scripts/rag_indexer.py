#!/usr/bin/env python3
"""
RAG Indexer for Nutrition Bot
Indexes nutrition knowledge base for semantic search
"""

import os
import json
import logging
from typing import List, Dict, Optional
from datetime import datetime
import chromadb
from chromadb.config import Settings
import tiktoken
import openai
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class NutritionRAGIndexer:
    def __init__(self, data_path: str, embeddings_path: str, openai_api_key: str):
        self.data_path = Path(data_path)
        self.embeddings_path = Path(embeddings_path)
        
        # Initialize OpenAI
        openai.api_key = openai_api_key
        self.client = openai.OpenAI(api_key=openai_api_key)
        
        # Initialize ChromaDB
        self.chroma_client = chromadb.PersistentClient(
            path=str(embeddings_path),
            settings=Settings(
                anonymized_telemetry=False,
                allow_reset=True
            )
        )
        
        # Create or get collection
        try:
            self.collection = self.chroma_client.get_collection("nutrition_knowledge")
            logger.info("Loaded existing collection")
        except:
            self.collection = self.chroma_client.create_collection(
                name="nutrition_knowledge",
                metadata={"hnsw:space": "cosine"}
            )
            logger.info("Created new collection")
        
        self.encoding = tiktoken.encoding_for_model("gpt-4")
        
    def chunk_text(self, text: str, chunk_size: int = 500, overlap: int = 50) -> List[str]:
        """Divide texto en chunks con overlap para mejor contexto"""
        tokens = self.encoding.encode(text)
        chunks = []
        
        start = 0
        while start < len(tokens):
            end = min(start + chunk_size, len(tokens))
            chunk_tokens = tokens[start:end]
            chunk_text = self.encoding.decode(chunk_tokens)
            chunks.append(chunk_text.strip())
            
            if end >= len(tokens):
                break
                
            start = end - overlap
            
        return [chunk for chunk in chunks if len(chunk.strip()) > 20]
    
    def extract_recipe_metadata(self, text: str, filename: str) -> Dict:
        """Extrae metadata específica de recetas"""
        metadata = {
            "source": filename,
            "type": "recipe",
            "meal_type": self._detect_meal_type(filename, text),
            "difficulty": self._detect_difficulty(text),
            "prep_time": self._extract_prep_time(text),
            "servings": self._extract_servings(text)
        }
        return metadata
    
    def _detect_meal_type(self, filename: str, text: str) -> str:
        """Detecta tipo de comida basado en archivo y contenido"""
        filename_lower = filename.lower()
        text_lower = text.lower()
        
        if 'desayuno' in filename_lower or any(word in text_lower for word in ['desayuno', 'mañana', 'café']):
            return 'desayuno'
        elif 'almuerzo' in filename_lower or any(word in text_lower for word in ['almuerzo', 'mediodía']):
            return 'almuerzo'
        elif 'merienda' in filename_lower or any(word in text_lower for word in ['merienda', 'tarde']):
            return 'merienda'
        elif 'cena' in filename_lower or any(word in text_lower for word in ['cena', 'noche']):
            return 'cena'
        else:
            return 'general'
    
    def _detect_difficulty(self, text: str) -> str:
        """Detecta dificultad de preparación"""
        text_lower = text.lower()
        
        if any(word in text_lower for word in ['fácil', 'simple', 'rápido', 'mezclar']):
            return 'facil'
        elif any(word in text_lower for word in ['cocinar', 'hornear', 'saltear']):
            return 'moderado'
        elif any(word in text_lower for word in ['complicado', 'elaborado', 'marinar']):
            return 'dificil'
        else:
            return 'moderado'
    
    def _extract_prep_time(self, text: str) -> Optional[str]:
        """Extrae tiempo de preparación si está mencionado"""
        import re
        time_pattern = r'(\d+)\s*(minutos?|min|horas?|hs?)'
        match = re.search(time_pattern, text.lower())
        return match.group(0) if match else None
    
    def _extract_servings(self, text: str) -> Optional[str]:
        """Extrae número de porciones si está mencionado"""
        import re
        servings_pattern = r'(\d+)\s*(porcion|porción|persona|serving)'
        match = re.search(servings_pattern, text.lower())
        return match.group(1) if match else None
    
    def load_and_index_files(self):
        """Carga y indexa todos los archivos de conocimiento"""
        documents = []
        metadatas = []
        ids = []
        
        logger.info(f"Scanning directory: {self.data_path}")
        
        for root, dirs, files in os.walk(self.data_path):
            for file in files:
                if file.endswith('.txt'):
                    file_path = os.path.join(root, file)
                    category = os.path.basename(root)
                    
                    logger.info(f"Processing: {file_path}")
                    
                    try:
                        with open(file_path, 'r', encoding='utf-8') as f:
                            content = f.read()
                        
                        if not content.strip():
                            logger.warning(f"Empty file: {file_path}")
                            continue
                        
                        chunks = self.chunk_text(content)
                        logger.info(f"Created {len(chunks)} chunks from {file}")
                        
                        for i, chunk in enumerate(chunks):
                            doc_id = f"{file.replace('.txt', '')}_{i}_{category}"
                            
                            metadata = {
                                "source": file,
                                "category": category,
                                "chunk_index": i,
                                "timestamp": datetime.now().isoformat(),
                                "file_path": file_path
                            }
                            
                            # Add specific metadata for recipes
                            if category == "recetas":
                                recipe_meta = self.extract_recipe_metadata(chunk, file)
                                metadata.update(recipe_meta)
                            
                            documents.append(chunk)
                            metadatas.append(metadata)
                            ids.append(doc_id)
                            
                    except Exception as e:
                        logger.error(f"Error processing {file_path}: {e}")
                        continue
        
        if not documents:
            logger.warning("No documents to index!")
            return
        
        # Clear existing collection and add new documents
        try:
            self.collection.delete(where={})
            logger.info("Cleared existing collection")
        except:
            pass
        
        # Add documents in batches
        batch_size = 100
        for i in range(0, len(documents), batch_size):
            batch_docs = documents[i:i+batch_size]
            batch_metas = metadatas[i:i+batch_size]
            batch_ids = ids[i:i+batch_size]
            
            self.collection.add(
                documents=batch_docs,
                metadatas=batch_metas,
                ids=batch_ids
            )
            logger.info(f"Indexed batch {i//batch_size + 1}/{(len(documents) + batch_size - 1)//batch_size}")
        
        logger.info(f"Successfully indexed {len(documents)} chunks from {len(set(m['source'] for m in metadatas))} files")
        
    def search(self, query: str, n_results: int = 5, category_filter: Optional[str] = None) -> List[Dict]:
        """Busca información relevante en la base de conocimiento"""
        where_clause = {}
        if category_filter:
            where_clause["category"] = category_filter
        
        try:
            results = self.collection.query(
                query_texts=[query],
                n_results=n_results,
                where=where_clause if where_clause else None
            )
            
            return [{
                "text": doc,
                "metadata": meta,
                "distance": dist
            } for doc, meta, dist in zip(
                results['documents'][0],
                results['metadatas'][0],
                results['distances'][0]
            )]
        except Exception as e:
            logger.error(f"Search error: {e}")
            return []

    def get_stats(self) -> Dict:
        """Obtiene estadísticas de la colección"""
        try:
            count = self.collection.count()
            
            # Get sample to analyze categories
            sample = self.collection.peek(limit=min(count, 100))
            categories = set()
            sources = set()
            
            for meta in sample.get('metadatas', []):
                if meta:
                    categories.add(meta.get('category', 'unknown'))
                    sources.add(meta.get('source', 'unknown'))
            
            return {
                "total_chunks": count,
                "categories": list(categories),
                "sources": list(sources),
                "collection_name": self.collection.name
            }
        except Exception as e:
            logger.error(f"Stats error: {e}")
            return {"error": str(e)}

if __name__ == "__main__":
    import sys
    
    # Configuration
    data_path = "/app/data"
    embeddings_path = "/app/embeddings"
    openai_api_key = os.getenv("OPENAI_API_KEY")
    
    if not openai_api_key:
        logger.error("OPENAI_API_KEY environment variable not set")
        sys.exit(1)
    
    # Create indexer and run
    indexer = NutritionRAGIndexer(data_path, embeddings_path, openai_api_key)
    
    if len(sys.argv) > 1 and sys.argv[1] == "search":
        # Test search
        query = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else "desayuno proteico"
        results = indexer.search(query, n_results=3)
        
        print(f"\nSearch results for: '{query}'")
        print("-" * 50)
        for i, result in enumerate(results, 1):
            print(f"{i}. Score: {result['distance']:.3f}")
            print(f"   Source: {result['metadata']['source']}")
            print(f"   Category: {result['metadata']['category']}")
            print(f"   Text: {result['text'][:200]}...")
            print()
    else:
        # Index files
        indexer.load_and_index_files()
        
        # Show stats
        stats = indexer.get_stats()
        print(f"\nIndexing complete!")
        print(f"Total chunks: {stats.get('total_chunks', 0)}")
        print(f"Categories: {', '.join(stats.get('categories', []))}")
        print(f"Sources: {len(stats.get('sources', []))} files")