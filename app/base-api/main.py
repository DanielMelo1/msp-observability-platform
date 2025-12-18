"""
Base API - Multi-tenant FastAPI application.

This application is deployed for all clients (Cliente A, B, C).
CLIENT_ID environment variable determines which client context it's serving.
"""
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from fastapi import FastAPI, Request
from fastapi.responses import Response
import logging
import time

from common.config import settings
from common.metrics import (
    http_requests_total,
    http_request_duration_seconds,
    get_metrics
)
from routes import health, items

# Configure logging
logging.basicConfig(
    level=settings.log_level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI application
app = FastAPI(
    title=f"MSP API - {settings.client_id}",
    description=f"Multi-tenant API serving client: {settings.client_id}",
    version="1.0.0"
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """
    Middleware to collect request metrics.
    
    Tracks:
    - Total requests by method, endpoint, status
    - Request duration histogram
    """
    start_time = time.time()
    
    response = await call_next(request)
    
    duration = time.time() - start_time
    
    # Record metrics
    http_requests_total.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code,
        client=settings.client_id
    ).inc()
    
    http_request_duration_seconds.labels(
        method=request.method,
        endpoint=request.url.path,
        client=settings.client_id
    ).observe(duration)
    
    return response


# Include routers
app.include_router(health.router, tags=["health"])
app.include_router(items.router, tags=["items"])


@app.get("/metrics")
async def metrics():
    """
    Prometheus metrics endpoint.
    
    Scraped by Zabbix agents for monitoring.
    Returns metrics in Prometheus text format.
    """
    metrics_content, content_type = get_metrics()
    return Response(content=metrics_content, media_type=content_type)


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "service": "MSP Multi-Tenant API",
        "client": settings.client_id,
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "ready": "/ready",
            "metrics": "/metrics",
            "items": "/api/items",
            "docs": "/docs"
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=False,
        workers=settings.workers
    )
