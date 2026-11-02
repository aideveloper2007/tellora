# GenAI Theme API

AI-powered theme generation service for e-commerce stores. This FastAPI service provides REST endpoints for conversational theme customization with support for PRD document upload.

## 🚀 Features

- **8 REST API Endpoints** for theme generation and management
- **Conversation-based** theme customization
- **PRD Document Upload** (PDF, DOCX, TXT, MD)
- **3 Template Types**: Luxury, Modern, Playful
- **8 Store Types**: Jewelry, Fashion, Electronics, Food, Sports, Kids, Tech, General
- **Mock LLM Mode** for development without API keys
- **7-Stage Validation** pipeline
- **Async Background Processing** for theme generation
- **Comprehensive Error Handling**

## 📋 Prerequisites

- Python 3.12+
- pip3
- Virtual environment (recommended)

## 🔧 Installation

### 1. Create Virtual Environment

```bash
cd genai_theme_api
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 2. Install Dependencies

```bash
pip install -r requirements.txt
```

### 3. Setup Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and configure:

```env
# For development (no API keys needed)
MOCK_LLM_MODE=True
MOCK_IMAGE_MODE=True

# For production (set API keys)
CLAUDE_API_KEY=your_claude_api_key
UNSPLASH_ACCESS_KEY=your_unsplash_access_key
MOCK_LLM_MODE=False
MOCK_IMAGE_MODE=False
```

## ▶️ Running the Server

### Development Mode (with auto-reload)

```bash
python3 app/main.py
```

Or using uvicorn directly:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Production Mode

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

The API will be available at:
- **API Base**: http://localhost:8000
- **Interactive Docs**: http://localhost:8000/api/docs
- **ReDoc**: http://localhost:8000/api/redoc

## 📚 API Endpoints

### Conversations

1. **POST /api/v1/conversations/start**
   - Start a new conversation
   - Returns conversation_id

2. **POST /api/v1/conversations/{id}/message**
   - Send message in conversation
   - AI extracts store information

3. **POST /api/v1/conversations/{id}/upload-prd**
   - Upload PRD document (PDF, DOCX, TXT, MD)
   - Max size: 10 MB

### Theme Generation

4. **POST /api/v1/themes/generate**
   - Generate theme (main endpoint)
   - Async background processing

5. **GET /api/v1/themes/{id}/status**
   - Check generation status
   - Get completed theme data

6. **POST /api/v1/themes/{id}/refine**
   - Refine existing theme
   - Natural language feedback

7. **POST /api/v1/themes/validate**
   - Validate theme quality
   - 7-stage validation

### Images

8. **POST /api/v1/images/fetch**
   - Fetch images by keywords
   - Uses Unsplash API (mock in dev mode)

## 🧪 Quick Test

### 1. Health Check

```bash
curl http://localhost:8000/health
```

### 2. Start Conversation

```bash
curl -X POST http://localhost:8000/api/v1/conversations/start \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user_123",
    "tenant_id": "mystore"
  }'
```

### 3. Generate Theme (Direct)

```bash
curl -X POST http://localhost:8000/api/v1/themes/generate \
  -H "Content-Type: application/json" \
  -d '{
    "store_type": "jewelry",
    "template": "template_luxury_001",
    "requirements": {
      "store_name": "Luxe Jewels",
      "style_keywords": ["elegant", "luxury"],
      "brand_colors": ["#C0C0C0", "#FFD700"]
    },
    "tenant_id": "mystore"
  }'
```

### 4. Check Status

```bash
curl http://localhost:8000/api/v1/themes/{theme_id}/status
```

## 🏗️ Project Structure

```
genai_theme_api/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI app entry point
│   ├── config.py                  # Configuration settings
│   ├── api/
│   │   └── v1/
│   │       ├── conversations.py   # Conversation endpoints
│   │       ├── themes.py          # Theme endpoints
│   │       └── images.py          # Image endpoints
│   ├── services/
│   │   └── mock_llm.py           # Mock LLM service
│   ├── schemas/
│   │   └── __init__.py           # Pydantic schemas
│   └── models/                   # Database models (future)
├── tests/                        # Test files
├── requirements.txt              # Python dependencies
├── .env.example                  # Environment template
├── .gitignore
└── README.md
```

## 🎨 Templates

### template_luxury_001 (Luxury)
- **Colors**: Silver, Gold, Black
- **Typography**: Playfair Display, Montserrat
- **Style**: Elegant, sophisticated
- **Best for**: Jewelry, Fashion, Accessories

### template_modern_002 (Modern)
- **Colors**: Blue, Teal, Orange
- **Typography**: Inter, Roboto
- **Style**: Clean, minimalist
- **Best for**: Electronics, Tech, General retail

### template_playful_003 (Playful)
- **Colors**: Coral, Turquoise, Yellow
- **Typography**: Fredoka One, Open Sans
- **Style**: Fun, vibrant
- **Best for**: Food, Kids, Sports

## 🔒 Store Types

- `jewelry` - Jewelry stores
- `fashion` - Fashion/clothing
- `electronics` - Electronic devices
- `food` - Food/restaurant
- `sports` - Sports/fitness
- `kids` - Kids/family products
- `tech` - Tech/software/SaaS
- `general` - General retail

## 📊 Validation Checks

1. **Structure Validation** - All required fields present
2. **Template Match** - Matches selected template (≥85%)
3. **Color Palette** - Complete color definitions
4. **Typography** - Proper font definitions
5. **CSS Generation** - Valid CSS output
6. **Content Quality** - Overall quality score (≥80%)
7. **Hallucination Check** - No fabricated content (≥90%)

## 🔄 Development Workflow

1. **Mock Mode** (Development)
   - Set `MOCK_LLM_MODE=True`
   - No API keys required
   - Instant responses
   - Perfect for testing

2. **Production Mode**
   - Set `MOCK_LLM_MODE=False`
   - Add Claude API key
   - Add Unsplash API key
   - Real LLM generation

## 🧩 Integration with Rails

### Example Rails Client Call

```ruby
# In Rails controller
response = HTTParty.post(
  "#{GENAI_API_URL}/api/v1/themes/generate",
  body: {
    store_type: "jewelry",
    template: "template_luxury_001",
    requirements: {
      store_name: current_tenant.name,
      style_keywords: ["elegant", "luxury"],
      brand_colors: current_tenant.brand_colors
    },
    tenant_id: current_tenant.subdomain
  }.to_json,
  headers: { 'Content-Type' => 'application/json' }
)

theme_id = response['theme_id']

# Poll for completion
while status = check_theme_status(theme_id)
  break if status['status'] == 'completed'
  sleep 2
end

# Apply theme to Spree
apply_theme_to_spree(status['theme_data'])
```

## 📝 Logging

Logs are written to:
- Console (stdout)
- `logs/api.log` (if configured)

Log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL

## 🐛 Troubleshooting

### Server won't start
```bash
# Check if port 8000 is in use
lsof -i :8000
# Kill process if needed
kill -9 <PID>
```

### Import errors
```bash
# Reinstall dependencies
pip install -r requirements.txt --force-reinstall
```

### Mock mode not working
```bash
# Verify .env file
cat .env | grep MOCK
# Should show: MOCK_LLM_MODE=True
```

## 📖 API Documentation

Once the server is running, visit:
- **Swagger UI**: http://localhost:8000/api/docs
- **ReDoc**: http://localhost:8000/api/redoc

Both provide:
- Interactive API testing
- Complete endpoint documentation
- Request/response schemas
- Example payloads

## 🚦 Next Steps

1. ✅ **Phase 1A-1B Complete**: API structure ready
2. 🔜 **Phase 1C**: Add real Claude LLM integration
3. 🔜 **Phase 2**: Integrate Unsplash API
4. 🔜 **Phase 3**: Add pytest test suite
5. 🔜 **Phase 4**: Build Rails client integration

## 📄 License

See LICENSE.md in project root

## 🤝 Support

For issues or questions:
1. Check API documentation: http://localhost:8000/api/docs
2. Review logs: `logs/api.log`
3. Check roadmap: `GENAI_THEME_ROADMAP.md`
