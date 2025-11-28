# BMM RNG Demo - Docker Image
# Note: BMM_RNG.py will be mounted at runtime during audit

FROM python:3.11-slim

WORKDIR /app

# Install system dependencies (sha256sum for checksum verification)
RUN apt-get update && apt-get install -y --no-install-recommends \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    fastapi==0.109.0 \
    uvicorn[standard]==0.27.0 \
    numpy==1.26.3

# Copy application (BMM_RNG.py will be added during audit)
COPY app.py .

# Expose port
EXPOSE 8000

# Run application
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
