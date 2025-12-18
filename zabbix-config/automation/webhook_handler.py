"""
Webhook Handler for Zabbix Triggers
Receives alerts from Zabbix and triggers auto-scaling actions
"""
from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel
import subprocess
import logging
import yaml
from pathlib import Path
from typing import Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Zabbix Webhook Handler")

# Load scaling policies
config_path = Path("/app/config/config.yaml")
with open(config_path) as f:
    config = yaml.safe_load(f)

SCALING_POLICIES = config.get("scaling_policies", {})


class TriggerPayload(BaseModel):
    """Zabbix trigger payload"""
    client: str
    namespace: str
    deployment: str
    metric: str
    action: str
    priority: Optional[str] = "normal"


def kubectl_scale(namespace: str, deployment: str, replicas: int) -> bool:
    """
    Scale Kubernetes deployment using kubectl
    
    Args:
        namespace: Kubernetes namespace
        deployment: Deployment name
        replicas: Target replica count
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        cmd = [
            "kubectl", "scale", "deployment", deployment,
            "--replicas", str(replicas),
            "-n", namespace
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0:
            logger.info(f"Scaled {namespace}/{deployment} to {replicas} replicas")
            return True
        else:
            logger.error(f"kubectl scale failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        logger.error(f"kubectl scale timeout for {namespace}/{deployment}")
        return False
    except Exception as e:
        logger.error(f"kubectl scale error: {e}")
        return False


def get_current_replicas(namespace: str, deployment: str) -> int:
    """Get current replica count"""
    try:
        cmd = [
            "kubectl", "get", "deployment", deployment,
            "-n", namespace,
            "-o", "jsonpath={.spec.replicas}"
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            return int(result.stdout.strip())
        else:
            logger.error(f"Failed to get replicas: {result.stderr}")
            return 0
            
    except Exception as e:
        logger.error(f"Error getting replicas: {e}")
        return 0


@app.post("/trigger")
async def handle_trigger(payload: TriggerPayload):
    """
    Handle Zabbix trigger webhook
    
    Receives trigger from Zabbix and scales deployment accordingly
    """
    logger.info(f"Received trigger: {payload.dict()}")
    
    # Get scaling policy for client
    policy = SCALING_POLICIES.get(payload.client)
    if not policy:
        logger.error(f"No scaling policy found for client: {payload.client}")
        raise HTTPException(status_code=404, detail="Client policy not found")
    
    # Get current replicas
    current_replicas = get_current_replicas(payload.namespace, payload.deployment)
    if current_replicas == 0:
        raise HTTPException(status_code=500, detail="Failed to get current replicas")
    
    # Calculate target replicas
    if payload.action == "scale_up":
        increment = policy.get("scale_up_increment", 1)
        target_replicas = min(
            current_replicas + increment,
            policy.get("max_replicas", 10)
        )
    elif payload.action == "scale_down":
        target_replicas = max(
            current_replicas - 1,
            policy.get("min_replicas", 1)
        )
    elif payload.action == "scale_to_minimum":
        target_replicas = policy.get("min_replicas", 1)
    else:
        raise HTTPException(status_code=400, detail="Invalid action")
    
    # Execute scaling
    if target_replicas != current_replicas:
        success = kubectl_scale(
            payload.namespace,
            payload.deployment,
            target_replicas
        )
        
        if success:
            return {
                "status": "success",
                "client": payload.client,
                "action": payload.action,
                "previous_replicas": current_replicas,
                "target_replicas": target_replicas
            }
        else:
            raise HTTPException(status_code=500, detail="Scaling failed")
    else:
        return {
            "status": "no_change",
            "message": f"Already at {current_replicas} replicas"
        }


@app.post("/optimize")
async def handle_cost_optimization(payload: TriggerPayload):
    """
    Handle cost optimization webhook
    
    Scales deployment to minimum during off-hours
    """
    logger.info(f"Cost optimization triggered for {payload.client}")
    
    policy = SCALING_POLICIES.get(payload.client)
    if not policy:
        raise HTTPException(status_code=404, detail="Client policy not found")
    
    min_replicas = policy.get("min_replicas", 1)
    
    success = kubectl_scale(
        payload.namespace,
        payload.deployment,
        min_replicas
    )
    
    if success:
        return {
            "status": "optimized",
            "client": payload.client,
            "replicas": min_replicas
        }
    else:
        raise HTTPException(status_code=500, detail="Optimization failed")


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
