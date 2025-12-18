FROM python:3.12-slim

WORKDIR /app

# Copy common modules first
COPY common/ /app/common/

# Copy application code
COPY base-api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY base-api/ .

# Run with Gunicorn for production
CMD ["gunicorn", "main:app", \
     "--workers", "4", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
