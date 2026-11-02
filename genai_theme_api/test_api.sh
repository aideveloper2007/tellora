#!/bin/bash

# GenAI Theme API - Quick Test Script
# This script tests all major endpoints of the API

echo "========================================="
echo "GenAI Theme API - Quick Test"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

API_URL="http://localhost:8000"

# Test 1: Health Check
echo -e "${BLUE}Test 1: Health Check${NC}"
curl -s $API_URL/health | python3 -m json.tool
echo ""
echo ""

# Test 2: Start Conversation
echo -e "${BLUE}Test 2: Start Conversation${NC}"
CONV_RESPONSE=$(curl -s -X POST $API_URL/api/v1/conversations/start \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test_user_123",
    "tenant_id": "teststore"
  }')

echo "$CONV_RESPONSE" | python3 -m json.tool
CONV_ID=$(echo "$CONV_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['conversation_id'])")
echo -e "${GREEN}Conversation ID: $CONV_ID${NC}"
echo ""
echo ""

# Test 3: Send Message
echo -e "${BLUE}Test 3: Send Message in Conversation${NC}"
curl -s -X POST $API_URL/api/v1/conversations/$CONV_ID/message \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I run a luxury jewelry store",
    "context": {
      "store_type": "jewelry"
    }
  }' | python3 -m json.tool
echo ""
echo ""

# Test 4: Generate Theme
echo -e "${BLUE}Test 4: Generate Theme${NC}"
THEME_RESPONSE=$(curl -s -X POST $API_URL/api/v1/themes/generate \
  -H "Content-Type: application/json" \
  -d '{
    "store_type": "jewelry",
    "template": "template_luxury_001",
    "requirements": {
      "store_name": "Luxe Jewels",
      "style_keywords": ["elegant", "luxury", "sophisticated"],
      "brand_colors": ["#C0C0C0", "#FFD700"],
      "target_audience": "High-end jewelry shoppers",
      "products": ["rings", "necklaces", "bracelets", "earrings"]
    },
    "tenant_id": "teststore"
  }')

echo "$THEME_RESPONSE" | python3 -m json.tool
THEME_ID=$(echo "$THEME_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['theme_id'])")
echo -e "${GREEN}Theme ID: $THEME_ID${NC}"
echo ""
echo ""

# Test 5: Check Theme Status (wait for completion)
echo -e "${BLUE}Test 5: Check Theme Status (waiting 3 seconds...)${NC}"
sleep 3
curl -s $API_URL/api/v1/themes/$THEME_ID/status | python3 -m json.tool | head -80
echo ""
echo "... (output truncated for readability)"
echo ""
echo ""

# Test 6: Fetch Images
echo -e "${BLUE}Test 6: Fetch Images${NC}"
curl -s -X POST $API_URL/api/v1/images/fetch \
  -H "Content-Type: application/json" \
  -d '{
    "keywords": ["jewelry", "luxury", "gold"],
    "count": 3,
    "orientation": "landscape"
  }' | python3 -m json.tool
echo ""
echo ""

# Test 7: Get Image Categories
echo -e "${BLUE}Test 7: Get Available Image Categories${NC}"
curl -s $API_URL/api/v1/images/categories | python3 -m json.tool | head -40
echo ""
echo "... (output truncated for readability)"
echo ""
echo ""

echo "========================================="
echo -e "${GREEN}All Tests Completed!${NC}"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. View full API docs: http://localhost:8000/api/docs"
echo "2. Get complete theme data: curl http://localhost:8000/api/v1/themes/$THEME_ID/status"
echo "3. Test theme refinement with feedback"
echo ""
