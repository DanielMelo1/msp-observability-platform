"""
Shared configuration for all MSP client applications.

This module provides common settings used across all client APIs,
including database connection, logging, and metrics configuration.
"""
import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Common application settings."""
    
    # Client identification
    client_id: str = os.getenv("CLIENT_ID", "unknown")
    
    # Database configuration
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql://app:app_password@localhost:5432/clientedb"
    )
    
    # API configuration
    api_host: str = os.getenv("API_HOST", "0.0.0.0")
    api_port: int = int(os.getenv("API_PORT", "8000"))
    workers: int = int(os.getenv("WORKERS", "4"))
    
    # Logging configuration
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    
    # Metrics configuration
    metrics_enabled: bool = os.getenv("METRICS_ENABLED", "true").lower() == "true"
    
    class Config:
        env_file = ".env"
        case_sensitive = False


# Global settings instance
settings = Settings()
