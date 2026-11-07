# Debian 12 (bookworm): Playwright's Chromium dependencies install cleanly on it
FROM python:3.11-slim-bookworm

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends libmagic1 curl && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# CPU-only PyTorch first (sentence-transformers would otherwise pull the huge GPU build)
RUN pip install --no-cache-dir --timeout 120 --retries 10 torch --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir --timeout 120 --retries 10 -r requirements.txt

# "Move my store": Pillow cuts and compares screenshots, Chromium renders the rebuilt design
RUN pip install --no-cache-dir --timeout 120 --retries 10 "Pillow>=10" "playwright==1.49.1" && \
    python -m playwright install --with-deps chromium && \
    rm -rf /var/lib/apt/lists/*

COPY . .

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]