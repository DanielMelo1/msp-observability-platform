#!/bin/bash
#
# Cleanup script - Destroys all resources
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "MSP Observability Platform - Cleanup"
echo "=========================================="
echo ""
echo -e "${RED}WARNING: This will destroy ALL resources!${NC}"
echo "  - EKS Cluster"
echo "  - VPC and networking"
echo "  - All applications"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Step 1: Deleting Kubernetes resources..."

kubectl delete -f k8s/cliente-a/ --ignore-not-found=true
kubectl delete -f k8s/cliente-b/ --ignore-not-found=true
kubectl delete -f k8s/cliente-c/ --ignore-not-found=true
kubectl delete -f k8s/zabbix/ --ignore-not-found=true

echo "Waiting for Load Balancers to be deleted..."
sleep 120

echo ""
echo "Step 2: Destroying Terraform infrastructure..."
cd terraform/environments/dev
terraform destroy -auto-approve

cd ../../..

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
echo "All AWS resources have been destroyed."
