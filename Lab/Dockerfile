FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements from root
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy all project files into /app
COPY . .

# Create keys directory where the KMS service expects it
RUN mkdir -p /app/keys

# Health check (Fixed the Python inline conditional bug)
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import httpx, os; port = os.environ.get('PORT', '8000'); httpx.get(f'http://localhost:{port}/health')" || exit 1

# Run using the new path format: folder 'app', file 'main', framework instance 'app'
CMD ["uvicorn", "app.app:app", "--host", "0.0.0.0", "--port", "8000"]