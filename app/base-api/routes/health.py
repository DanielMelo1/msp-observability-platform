"""
Health check endpoints for Kubernetes probes.

These endpoints are used by:
- Kubernetes liveness probes (is container alive?)
- Kubernetes readiness probes (can container serve traffic?)
- Load balancer health checks
"""
from fastapi import APIRouter, status
from datetime import datetime

router = APIRouter()


@router.get("/health", status_code=status.HTTP_200_OK)
async def health_check():
    """
    Basic health check endpoint.
    
    Returns 200 OK if application is running.
    Used by Kubernetes liveness probe.
    """
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat()
    }


@router.get("/ready", status_code=status.HTTP_200_OK)
async def readiness_check():
    """
    Readiness check endpoint.
    
    Returns 200 OK if application can serve traffic.
    Used by Kubernetes readiness probe.
    
    In production, this would check:
    - Database connectivity
    - External service availability
    - Cache readiness
    """
    return {
        "status": "ready",
        "timestamp": datetime.utcnow().isoformat()
    }
