# Quick Start Guide - AI Theme Designer

## 🚀 Quick Setup (5 Minutes)

### 1. Run Database Migrations

```bash
cd /mnt/c/Users/amars/OneDrive/Documents/saas-premium-main
rails db:migrate
```

### 2. Setup Python Service

```bash
# Navigate to python service
cd python_service

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Setup environment
cp .env.example .env
```

### 3. Configure API Keys

Edit `python_service/.env`:

```bash
# Choose your LLM provider
LLM_PROVIDER=openai

# Add your API key
OPENAI_API_KEY=sk-your-key-here

# OR for Anthropic
# LLM_PROVIDER=anthropic
# ANTHROPIC_API_KEY=your-key-here
```

### 4. Start Services

**Terminal 1 - Python Service:**
```bash
cd python_service
source venv/bin/activate
python main.py
```

**Terminal 2 - Rails Server:**
```bash
cd /mnt/c/Users/amars/OneDrive/Documents/saas-premium-main
rails server
```

### 5. Test It!

1. Open browser: http://localhost:3000/tenant_registrations/new
2. Click "Launch Theme Designer"
3. Start chatting or upload a PRD document!

## 🎯 Quick Test Prompts

Try these in the chatbot:

1. **Simple Theme:**
   ```
   Create a modern blue theme for a tech store
   ```

2. **Detailed Theme:**
   ```
   I want a luxury fashion store with:
   - Black and gold colors
   - Elegant serif fonts
   - Minimalist design
   ```

3. **Upload Test:**
   - Create a simple text file with store requirements
   - Upload via the 📎 button
   - Let AI analyze and generate

## 📝 PRD Document Template

Create `test_prd.txt`:

```
Store Design Requirements

Brand: Modern Tech Store
Target Audience: Tech enthusiasts, 25-45 years old

Colors:
- Primary: Blue (#3b82f6)
- Secondary: Gray (#64748b)
- Accent: Orange (#f59e0b)

Typography:
- Headings: Inter, bold
- Body: Inter, regular

Layout:
- Clean, modern grid
- 3-column product display
- Sticky header
- Detailed footer with links

Features:
- Product quick view
- Wishlist functionality
- Modern checkout flow
```

Upload this and watch the magic happen! ✨

## 🐛 Troubleshooting

**Python service won't start:**
```bash
# Check Python version (need 3.10+)
python3 --version

# Reinstall dependencies
pip install --upgrade -r requirements.txt
```

**No API response:**
```bash
# Test Python service
curl http://localhost:8000/health

# Check logs
# Python service will show logs in the terminal
```

**Database errors:**
```bash
# Reset and remigrate
rails db:migrate:reset
rails db:migrate
```

## 🎉 You're Ready!

The chatbot is now live at:
**http://localhost:3000/theme_designer**

Have fun designing themes with AI! 🤖✨
