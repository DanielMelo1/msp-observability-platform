#!/bin/bash
#
# Setup script for MSP Observability Platform
# Deploys complete infrastructure and applications
#

set -e

echo "=========================================="
echo "MSP Observability Platform - Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "Checking prerequisites..."

command -v terraform >/dev/null 2>&1 || { echo -e "${RED}ERROR: terraform not installed${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}ERROR: kubectl not installed${NC}"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}ERROR: aws cli not installed${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}ERROR: helm not installed${NC}"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo -e "${RED}ERROR: docker not installed${NC}"; exit 1; }

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Verify AWS credentials
echo "Verifying AWS credentials..."
aws sts get-caller-identity >/dev/null 2>&1 || { echo -e "${RED}ERROR: AWS credentials not configured${NC}"; exit 1; }
echo -e "${GREEN}✓ AWS credentials verified${NC}"
echo ""

# Deploy Terraform infrastructure
echo "=========================================="
echo "Step 1: Deploying Infrastructure (Terraform)"
echo "=========================================="
echo "This will create:"
echo "  - VPC with public/private subnets"
echo "  - EKS cluster"
echo "  - 3 worker nodes (t3.medium)"
echo "  - Estimated time: ~15 minutes"
echo ""
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

cd terraform/environments/dev
terraform init
terraform plan
terraform apply -auto-approve

# Save outputs
terraform output -json > outputs.json
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
VPC_ID=$(terraform output -raw vpc_id)

echo -e "${GREEN}✓ Infrastructure deployed${NC}"
echo ""

cd ../../..

# Configure kubectl
echo "=========================================="
echo "Step 2: Configuring kubectl"
echo "=========================================="
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
kubectl get nodes

echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# Install AWS Load Balancer Controller
echo "=========================================="
echo "Step 3: Installing AWS Load Balancer Controller"
echo "=========================================="

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

# Uninstall if exists
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
sleep 10

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID \
  --timeout 10m \
  --wait

echo -e "${GREEN}✓ Load Balancer Controller installed${NC}"
echo ""

# Build Docker images
echo "=========================================="
echo "Step 4: Building Docker Images"
echo "=========================================="

echo "Building base-api..."
docker build -t base-api:latest -f app/base-api/Dockerfile app/ || { echo -e "${RED}ERROR: Failed to build base-api${NC}"; exit 1; }

echo "Building webhook-handler..."
docker build -t webhook-handler:latest -f zabbix-config/automation/Dockerfile zabbix-config/automation/ || { echo -e "${RED}ERROR: Failed to build webhook-handler${NC}"; exit 1; }

echo -e "${GREEN}✓ Docker images built${NC}"
echo ""

# Deploy Kubernetes resources
echo "=========================================="
echo "Step 5: Deploying Applications"
echo "=========================================="

echo "Deploying Zabbix monitoring..."
kubectl apply -f k8s/zabbix/

echo "Waiting for Zabbix to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=ready pod -l app=zabbix-server -n monitoring --timeout=300s 2>/dev/null || echo -e "${YELLOW}Note: Zabbix may still be starting${NC}"

echo "Deploying client applications..."
kubectl apply -f k8s/cliente-a/
kubectl apply -f k8s/cliente-b/
kubectl apply -f k8s/cliente-c/

echo "Deploying monitoring services..."
kubectl apply -f k8s/monitoring/

echo -e "${GREEN}✓ Applications deployed${NC}"
echo ""

# Wait for Ingress
echo "=========================================="
echo "Step 6: Waiting for Load Balancer"
echo "=========================================="

echo "Waiting for ALB to be provisioned (this may take 2-3 minutes)..."
sleep 120

ALB_DNS=$(kubectl get ingress -n cliente-a cliente-a-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$ALB_DNS" ]; then
    echo -e "${YELLOW}WARNING: ALB not ready yet. Check with: kubectl get ingress -A${NC}"
else
    echo -e "${GREEN}✓ ALB provisioned: $ALB_DNS${NC}"
fi
echo ""

# Summary
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "VPC: $VPC_ID"
echo ""
echo "Check application status:"
echo "  kubectl get pods -A"
echo "  kubectl get ingress -A"
echo ""
echo "Access Zabbix:"
echo "  kubectl port-forward -n monitoring svc/zabbix-frontend 8080:80"
echo "  Then open: http://localhost:8080"
echo "  Login: Admin / zabbix"
echo ""
echo "To destroy everything: ./scripts/cleanup.sh"
echo ""
