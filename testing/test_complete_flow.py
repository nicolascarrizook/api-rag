#!/usr/bin/env python3
"""
Script de testing completo para el flujo:
Telegram Bot → n8n → RAG API → OpenAI
"""

import os
import json
import time
import requests
from typing import Dict, Any, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TelegramBotTester:
    """Test suite for the complete nutrition bot flow"""
    
    def __init__(self, rag_api_url: str, n8n_webhook_url: str):
        self.rag_api_url = rag_api_url.rstrip('/')
        self.n8n_webhook_url = n8n_webhook_url.rstrip('/')
        self.test_user_id = 123456789
        
    def test_rag_api_health(self) -> bool:
        """Test RAG API health"""
        try:
            logger.info("🔍 Testing RAG API health...")
            response = requests.get(f"{self.rag_api_url}/health", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                logger.info(f"✅ RAG API health: {data}")
                return data.get("status") == "healthy"
            else:
                logger.error(f"❌ RAG API health check failed: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"❌ RAG API connection error: {e}")
            return False
    
    def test_rag_api_search(self) -> bool:
        """Test RAG API search functionality"""
        try:
            logger.info("🔍 Testing RAG API search...")
            
            # Test query
            query = "plan nutricional para bajar peso moderado 30 años"
            response = requests.get(
                f"{self.rag_api_url}/search",
                params={"q": query, "max_results": 3},
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                results_count = len(data.get("results", []))
                logger.info(f"✅ RAG search returned {results_count} results")
                
                if results_count > 0:
                    logger.info(f"📄 Sample result: {data['results'][0]['content'][:100]}...")
                    return True
                else:
                    logger.warning("⚠️ No search results found - check if documents are uploaded")
                    return False
            else:
                logger.error(f"❌ RAG search failed: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"❌ RAG search error: {e}")
            return False
    
    def test_rag_api_documents(self) -> bool:
        """Test RAG API document listing"""
        try:
            logger.info("🔍 Testing RAG API documents...")
            response = requests.get(f"{self.rag_api_url}/documents", timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                doc_count = data.get("total_documents", 0)
                chunk_count = data.get("total_chunks", 0)
                
                logger.info(f"✅ RAG has {doc_count} documents with {chunk_count} chunks")
                
                if doc_count > 0:
                    for doc in data.get("documents", [])[:3]:
                        logger.info(f"📄 {doc['filename']} - {doc['chunks']} chunks")
                    return True
                else:
                    logger.warning("⚠️ No documents found - upload some Word documents first")
                    return False
            else:
                logger.error(f"❌ RAG documents check failed: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"❌ RAG documents error: {e}")
            return False
    
    def test_n8n_webhook(self) -> bool:
        """Test n8n webhook with complete patient data"""
        try:
            logger.info("🔍 Testing n8n webhook...")
            
            # Sample patient data
            patient_data = {
                "user_id": self.test_user_id,
                "action": "generate_plan",
                "type": "nuevo",
                "patient_data": {
                    "nombre": "Juan Pérez Test",
                    "edad": 30,
                    "peso": 75.5,
                    "altura": 175,
                    "objetivo": "⬇️ Bajar 0.5kg/semana",
                    "actividad": "🏃 Moderado"
                }
            }
            
            logger.info(f"📤 Sending test data to n8n: {json.dumps(patient_data, indent=2)}")
            
            response = requests.post(
                self.n8n_webhook_url,
                json=patient_data,
                timeout=60,  # n8n might take time with OpenAI
                headers={"Content-Type": "application/json"}
            )
            
            if response.status_code == 200:
                try:
                    data = response.json()
                    logger.info(f"✅ n8n webhook response: {data}")
                    
                    if data.get("success"):
                        logger.info("🎉 Complete flow test successful!")
                        return True
                    else:
                        logger.error(f"❌ n8n returned error: {data.get('error', 'Unknown error')}")
                        return False
                        
                except json.JSONDecodeError:
                    logger.info(f"✅ n8n webhook accepted request (non-JSON response)")
                    logger.info(f"Response: {response.text[:200]}...")
                    return True
            else:
                logger.error(f"❌ n8n webhook failed: {response.status_code}")
                logger.error(f"Response: {response.text}")
                return False
                
        except requests.exceptions.Timeout:
            logger.error("❌ n8n webhook timeout - check if OpenAI is responding")
            return False
        except Exception as e:
            logger.error(f"❌ n8n webhook error: {e}")
            return False
    
    def test_individual_components(self) -> bool:
        """Test each component individually"""
        logger.info("🧪 Testing individual components...")
        
        tests = [
            ("RAG API Health", self.test_rag_api_health),
            ("RAG API Documents", self.test_rag_api_documents),
            ("RAG API Search", self.test_rag_api_search),
        ]
        
        results = {}
        for test_name, test_func in tests:
            logger.info(f"\n--- {test_name} ---")
            results[test_name] = test_func()
            time.sleep(1)  # Brief pause between tests
        
        # Summary
        logger.info("\n📊 Individual Component Test Results:")
        for test_name, result in results.items():
            status = "✅ PASS" if result else "❌ FAIL"
            logger.info(f"  {test_name}: {status}")
        
        return all(results.values())
    
    def test_complete_flow(self) -> bool:
        """Test the complete flow end-to-end"""
        logger.info("\n🚀 Testing complete flow...")
        
        # First test individual components
        if not self.test_individual_components():
            logger.error("❌ Individual components failed, skipping flow test")
            return False
        
        # Test complete flow
        logger.info("\n--- Complete Flow Test ---")
        return self.test_n8n_webhook()
    
    def run_all_tests(self):
        """Run all tests and provide summary"""
        logger.info("🧪 Starting complete test suite for Nutrition Bot")
        logger.info(f"RAG API URL: {self.rag_api_url}")
        logger.info(f"n8n Webhook URL: {self.n8n_webhook_url}")
        logger.info(f"Test User ID: {self.test_user_id}")
        
        start_time = time.time()
        
        # Run tests
        individual_success = self.test_individual_components()
        flow_success = False
        
        if individual_success:
            flow_success = self.test_n8n_webhook()
        
        # Final summary
        duration = time.time() - start_time
        logger.info(f"\n🏁 Test Suite Complete ({duration:.1f}s)")
        logger.info("=" * 50)
        
        if individual_success and flow_success:
            logger.info("🎉 ALL TESTS PASSED!")
            logger.info("✅ Your nutrition bot is ready to use!")
            logger.info("\nNext steps:")
            logger.info("1. Start your Telegram bot: python nutrition_bot.py")
            logger.info("2. Test with Telegram: @your_bot_username")
            logger.info("3. Try creating a new nutrition plan")
        elif individual_success:
            logger.warning("⚠️ INDIVIDUAL TESTS PASSED, FLOW TEST FAILED")
            logger.warning("Check your n8n workflow configuration")
        else:
            logger.error("❌ TESTS FAILED")
            logger.error("Fix the failing components before proceeding")
        
        return individual_success and flow_success

def main():
    """Main function with command line interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Test the complete nutrition bot flow")
    parser.add_argument(
        "--rag-api-url",
        default="http://localhost:8001",
        help="RAG API URL (default: http://localhost:8001)"
    )
    parser.add_argument(
        "--n8n-webhook-url",
        required=True,
        help="n8n webhook URL (e.g., https://your-n8n.com/webhook/telegram-nutrition)"
    )
    parser.add_argument(
        "--test-individual",
        action="store_true",
        help="Test only individual components, skip flow test"
    )
    parser.add_argument(
        "--test-flow-only",
        action="store_true",
        help="Test only the complete flow, skip individual tests"
    )
    
    args = parser.parse_args()
    
    # Validate URLs
    if not args.rag_api_url.startswith(("http://", "https://")):
        logger.error("RAG API URL must start with http:// or https://")
        return 1
    
    if not args.n8n_webhook_url.startswith(("http://", "https://")):
        logger.error("n8n webhook URL must start with http:// or https://")
        return 1
    
    # Create tester
    tester = TelegramBotTester(args.rag_api_url, args.n8n_webhook_url)
    
    # Run appropriate tests
    if args.test_individual:
        success = tester.test_individual_components()
    elif args.test_flow_only:
        success = tester.test_n8n_webhook()
    else:
        success = tester.run_all_tests()
    
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())