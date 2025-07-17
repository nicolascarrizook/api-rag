#!/usr/bin/env python3
"""
Script para procesar automáticamente documentos Word y subirlos a la API RAG
Procesa todos los archivos .docx en un directorio y los indexa
"""

import os
import sys
import requests
import argparse
from pathlib import Path
from typing import List
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def upload_document(file_path: Path, api_url: str) -> bool:
    """
    Upload a single document to the RAG API
    
    Args:
        file_path: Path to the document
        api_url: Base URL of the RAG API
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        upload_endpoint = f"{api_url}/upload"
        
        with open(file_path, 'rb') as file:
            files = {'file': (file_path.name, file, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')}
            
            logger.info(f"Uploading {file_path.name}...")
            
            response = requests.post(
                upload_endpoint,
                files=files,
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                logger.info(f"✅ {file_path.name} - {result['chunks']} chunks processed")
                return True
            else:
                logger.error(f"❌ {file_path.name} - Error {response.status_code}: {response.text}")
                return False
                
    except requests.exceptions.Timeout:
        logger.error(f"❌ {file_path.name} - Timeout error")
        return False
    except requests.exceptions.ConnectionError:
        logger.error(f"❌ {file_path.name} - Connection error. Is the RAG API running?")
        return False
    except Exception as e:
        logger.error(f"❌ {file_path.name} - Error: {str(e)}")
        return False

def find_word_documents(directory: Path) -> List[Path]:
    """
    Find all Word documents in a directory
    
    Args:
        directory: Directory to search
        
    Returns:
        List of Path objects for Word documents
    """
    word_files = []
    
    # Search for .docx files
    for file_path in directory.rglob("*.docx"):
        # Skip temporary files
        if not file_path.name.startswith("~$"):
            word_files.append(file_path)
    
    # Search for .doc files (legacy)
    for file_path in directory.rglob("*.doc"):
        # Skip temporary files
        if not file_path.name.startswith("~$"):
            word_files.append(file_path)
    
    return sorted(word_files)

def check_api_health(api_url: str) -> bool:
    """
    Check if the RAG API is healthy
    
    Args:
        api_url: Base URL of the RAG API
        
    Returns:
        bool: True if healthy, False otherwise
    """
    try:
        health_endpoint = f"{api_url}/health"
        response = requests.get(health_endpoint, timeout=10)
        
        if response.status_code == 200:
            health_data = response.json()
            if health_data.get("status") == "healthy":
                logger.info("✅ RAG API is healthy")
                return True
            else:
                logger.error("❌ RAG API is not healthy")
                return False
        else:
            logger.error(f"❌ RAG API health check failed: {response.status_code}")
            return False
            
    except Exception as e:
        logger.error(f"❌ Cannot connect to RAG API: {str(e)}")
        return False

def list_existing_documents(api_url: str) -> List[str]:
    """
    Get list of documents already in the RAG API
    
    Args:
        api_url: Base URL of the RAG API
        
    Returns:
        List of filenames already processed
    """
    try:
        docs_endpoint = f"{api_url}/documents"
        response = requests.get(docs_endpoint, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            existing_files = [doc['filename'] for doc in data.get('documents', [])]
            logger.info(f"📋 Found {len(existing_files)} existing documents in RAG")
            return existing_files
        else:
            logger.warning(f"Could not fetch existing documents: {response.status_code}")
            return []
            
    except Exception as e:
        logger.warning(f"Could not fetch existing documents: {str(e)}")
        return []

def clear_existing_documents(api_url: str) -> bool:
    """
    Clear all existing documents from the RAG API
    
    Args:
        api_url: Base URL of the RAG API
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        clear_endpoint = f"{api_url}/documents"
        response = requests.delete(clear_endpoint, timeout=30)
        
        if response.status_code == 200:
            logger.info("✅ Cleared all existing documents")
            return True
        else:
            logger.error(f"❌ Could not clear documents: {response.status_code}")
            return False
            
    except Exception as e:
        logger.error(f"❌ Error clearing documents: {str(e)}")
        return False

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="Process Word documents and upload to RAG API"
    )
    parser.add_argument(
        "directory",
        type=str,
        help="Directory containing Word documents"
    )
    parser.add_argument(
        "--api-url",
        type=str,
        default="http://localhost:8001",
        help="RAG API base URL (default: http://localhost:8001)"
    )
    parser.add_argument(
        "--clear",
        action="store_true",
        help="Clear existing documents before uploading"
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip files that already exist in the RAG API"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be processed without actually uploading"
    )
    
    args = parser.parse_args()
    
    # Validate directory
    doc_directory = Path(args.directory)
    if not doc_directory.exists():
        logger.error(f"Directory does not exist: {doc_directory}")
        sys.exit(1)
    
    if not doc_directory.is_dir():
        logger.error(f"Path is not a directory: {doc_directory}")
        sys.exit(1)
    
    # Check API health
    if not args.dry_run:
        if not check_api_health(args.api_url):
            logger.error("RAG API is not available. Please start the API first.")
            sys.exit(1)
    
    # Find Word documents
    logger.info(f"🔍 Searching for Word documents in: {doc_directory}")
    word_documents = find_word_documents(doc_directory)
    
    if not word_documents:
        logger.warning("No Word documents found")
        return
    
    logger.info(f"📄 Found {len(word_documents)} Word documents")
    
    # Show found files
    for doc in word_documents:
        relative_path = doc.relative_to(doc_directory)
        file_size = doc.stat().st_size / 1024  # KB
        logger.info(f"  📄 {relative_path} ({file_size:.1f} KB)")
    
    if args.dry_run:
        logger.info("🏃 Dry run mode - no files will be uploaded")
        return
    
    # Get existing documents if skip-existing is enabled
    existing_documents = []
    if args.skip_existing:
        existing_documents = list_existing_documents(args.api_url)
    
    # Clear existing documents if requested
    if args.clear:
        if input("⚠️  Clear all existing documents? (y/N): ").lower() == 'y':
            clear_existing_documents(args.api_url)
        else:
            logger.info("Skipping clear operation")
    
    # Process documents
    logger.info("🚀 Starting document processing...")
    
    processed = 0
    skipped = 0
    failed = 0
    
    for doc_path in word_documents:
        # Check if should skip
        if args.skip_existing and doc_path.name in existing_documents:
            logger.info(f"⏭️  Skipping {doc_path.name} (already exists)")
            skipped += 1
            continue
        
        # Upload document
        if upload_document(doc_path, args.api_url):
            processed += 1
        else:
            failed += 1
    
    # Summary
    logger.info("📊 Processing complete!")
    logger.info(f"  ✅ Processed: {processed}")
    logger.info(f"  ⏭️  Skipped: {skipped}")
    logger.info(f"  ❌ Failed: {failed}")
    
    if failed > 0:
        logger.warning("Some documents failed to process. Check the logs above.")
        sys.exit(1)
    else:
        logger.info("🎉 All documents processed successfully!")

if __name__ == "__main__":
    main()