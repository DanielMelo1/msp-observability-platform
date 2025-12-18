"""
Cost Optimizer - Scheduled scaling for off-hours
Runs as CronJob in Kubernetes to scale down non-critical workloads
"""
import subprocess
import logging
from datetime import datetime
import requests
import os

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Cost optimization schedule
COST_OPTIMIZATION_CONFIG = {
    'cliente-c': {
        'business_hours_start': 8,   # 8 AM
        'business_hours_end': 20,     # 8 PM
        'off_hours_replicas': 1,
        'business_hours_min': 2
    }
}

WEBHOOK_URL = os.getenv(
    'WEBHOOK_URL',
    'http://webhook-handler.monitoring.svc.cluster.local:8080'
)


def is_business_hours(config: dict) -> bool:
    """Check if current time is within business hours"""
    now = datetime.now()
    current_hour = now.hour
    
    start = config['business_hours_start']
    end = config['business_hours_end']
    
    return start <= current_hour < end


def optimize_client(client: str, config: dict):
    """
    Optimize client resources based on time of day
    
    Args:
        client: Client identifier
        config: Optimization configuration
    """
    logger.info(f"Processing cost optimization for {client}")
    
    if is_business_hours(config):
        logger.info(f"{client}: Business hours - maintaining normal operation")
        return
    
    # Off-hours: scale to minimum
    logger.info(f"{client}: Off-hours detected - scaling to minimum")
    
    payload = {
        "client": client,
        "namespace": client,
        "deployment": f"{client}-api",
        "metric": "schedule",
        "action": "scale_to_minimum"
    }
    
    try:
        response = requests.post(
            f"{WEBHOOK_URL}/optimize",
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            logger.info(f"Successfully optimized {client}: {result}")
        else:
            logger.error(f"Optimization failed for {client}: {response.text}")
            
    except requests.exceptions.RequestException as e:
        logger.error(f"Request failed for {client}: {e}")


def main():
    """Main cost optimization routine"""
    logger.info("=" * 50)
    logger.info("Cost Optimizer - Starting")
    logger.info(f"Current time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 50)
    
    for client, config in COST_OPTIMIZATION_CONFIG.items():
        try:
            optimize_client(client, config)
        except Exception as e:
            logger.error(f"Error optimizing {client}: {e}")
    
    logger.info("Cost optimization complete")


if __name__ == "__main__":
    main()
