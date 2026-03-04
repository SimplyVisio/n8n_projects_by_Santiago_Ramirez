FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for psycopg2 and other libs
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install nest-asyncio

COPY . .

# Expose FastAPI port
EXPOSE 8000

# Entrypoint will be overridden in docker-compose for api/worker
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
