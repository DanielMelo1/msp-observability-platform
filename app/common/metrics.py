"""
Prometheus metrics shared across all client applications.

These metrics are scraped by Zabbix for monitoring and alerting.
All client applications export the same metric types for consistency.
"""
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST


# HTTP Request metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status', 'client']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint', 'client'],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0)
)

# Application metrics
active_connections = Gauge(
    'active_database_connections',
    'Number of active database connections',
    ['client']
)

application_info = Gauge(
    'application_info',
    'Application information',
    ['client', 'version']
)


def get_metrics():
    """
    Generate Prometheus metrics in text format.
    
    Returns:
        tuple: (metrics_content, content_type)
    """
    return generate_latest(), CONTENT_TYPE_LATEST
