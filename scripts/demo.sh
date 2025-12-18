#!/bin/bash
#
# Demo script - Shows auto-scaling in action
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "MSP Observability Platform - Demo"
echo "=========================================="
echo ""

# Check if cluster is accessible
kubectl cluster-info >/dev/null 2>&1 || { echo "ERROR: Cannot connect to cluster"; exit 1; }

echo "Current cluster status:"
kubectl get nodes
echo ""

echo "Current pods:"
kubectl get pods -n cliente-a
kubectl get pods -n cliente-b
kubectl get pods -n cliente-c
echo ""

echo "HPA status:"
kubectl get hpa -n cliente-a
kubectl get hpa -n cliente-b
kubectl get hpa -n cliente-c
echo ""

echo -e "${GREEN}Starting load test on Cliente A...${NC}"
echo "This will trigger auto-scaling (watch pods increase)"
echo ""

# Generate load
kubectl run load-generator --image=busybox --restart=Never -n cliente-a \
  -- /bin/sh -c "while true; do wget -q -O- http://cliente-a-api:8000/api/items; done" &

LOAD_PID=$!

echo "Watching auto-scaling (press Ctrl+C to stop)..."
echo ""

# Watch for 5 minutes
watch -n 5 'kubectl get hpa -n cliente-a; echo ""; kubectl get pods -n cliente-a'

# Cleanup
kubectl delete pod load-generator -n cliente-a 2>/dev/null || true

echo ""
echo -e "${GREEN}Demo complete!${NC}"
