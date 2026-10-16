# =============================================================================
# DevOps Final Project - Multi-stage Dockerfile
# Stage 1: builder - installs Python dependencies
# Stage 2: final   - runtime image with non-root user
# =============================================================================

FROM python:3.11-slim AS builder

WORKDIR /app

# Copy and install Python dependencies
COPY application/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# -----------------------------------------------------------------------------
# Final stage
# -----------------------------------------------------------------------------
FROM python:3.11-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY application/ ./application/

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser -s /sbin/nologin appuser \
    && chown -R appuser:appuser /app

USER appuser

# Expose application port
EXPOSE 5000

# Healthcheck used by Kubernetes liveness probe and Docker HEALTHCHECK
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=3)"]

# Run with gunicorn (production WSGI server)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "application.app:app"]
