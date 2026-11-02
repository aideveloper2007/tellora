# Python GenAI Theme Service

AI-powered theme generation microservice for the ecommerce platform.

## Setup

1. Install Python 3.10 or higher
2. Create virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env and add your API keys
   ```

5. Run the service:
   ```bash
   python main.py
   ```

The service will start on http://localhost:8000

## API Endpoints

- `GET /health` - Health check
- `POST /api/chat` - Conversational chat
- `POST /api/parse-prd` - Parse PRD documents
- `POST /api/generate-theme` - Generate theme configuration
- `POST /api/test-llm` - Test LLM connectivity

## LLM Providers

Supports:
- OpenAI (GPT-4, GPT-3.5)
- Anthropic (Claude)
- Ollama (local models - for future)

Configure via `LLM_PROVIDER` in `.env`
