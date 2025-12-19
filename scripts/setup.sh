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
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS credentials verified (Account: $ACCOUNT_ID)${NC}"
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

# Install Metrics Server
echo "=========================================="
echo "Step 4: Installing Metrics Server"
echo "=========================================="

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
sleep 30

echo -e "${GREEN}✓ Metrics Server installed${NC}"
echo ""

# Setup EBS CSI Driver IRSA
echo "=========================================="
echo "Step 5: Configuring EBS CSI Driver"
echo "=========================================="

# Get OIDC ID
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
echo "OIDC ID: $OIDC_ID"

# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://oidc.eks.$REGION.amazonaws.com/id/$OIDC_ID \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 \
  --region $REGION 2>/dev/null || echo "OIDC provider already exists"

# Create trust policy
cat > /tmp/ebs-csi-trust-policy.json << TRUST_EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/oidc.eks.$REGION.amazonaws.com/id/$OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.$REGION.amazonaws.com/id/$OIDC_ID:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
          "oidc.eks.$REGION.amazonaws.com/id/$OIDC_ID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
TRUST_EOF

# Create IAM role for EBS CSI
aws iam create-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --assume-role-policy-document file:///tmp/ebs-csi-trust-policy.json \
  --region $REGION 2>/dev/null || echo "Role already exists"

# Attach policy
POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AmazonEKS_EBS_CSI_Driver_Policy`].Arn' --output text)
if [ -z "$POLICY_ARN" ]; then
    echo "Creating EBS CSI Driver policy..."
    POLICY_ARN=$(aws iam create-policy \
      --policy-name AmazonEKS_EBS_CSI_Driver_Policy \
      --policy-document file://<(cat <<'POLICY_EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*"
    }
  ]
}
POLICY_EOF
) --query 'Policy.Arn' --output text)
fi

aws iam attach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn $POLICY_ARN

# Annotate service account
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::$ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole \
  --overwrite

# Restart EBS CSI controller
kubectl rollout restart deployment ebs-csi-controller -n kube-system
sleep 90

echo -e "${GREEN}✓ EBS CSI Driver configured${NC}"
echo ""

# Build and Push Docker images
echo "=========================================="
echo "Step 6: Building Docker Images"
echo "=========================================="

echo "Building base-api..."
docker build -t base-api:latest -f app/base-api/Dockerfile app/

echo "Building webhook-handler..."
docker build -t webhook-handler:latest -f zabbix-config/automation/Dockerfile zabbix-config/automation/

# Tag for GHCR
docker tag base-api:latest ghcr.io/danielmelo1/base-api:latest
docker tag webhook-handler:latest ghcr.io/danielmelo1/webhook-handler:latest

echo ""
echo -e "${YELLOW}NOTE: Images are available at:${NC}"
echo "  - ghcr.io/danielmelo1/base-api:latest"
echo "  - ghcr.io/danielmelo1/webhook-handler:latest"
echo ""
echo -e "${YELLOW}If you want to push your own images:${NC}"
echo "  1. Login to GHCR: docker login ghcr.io"
echo "  2. Push: docker push ghcr.io/YOUR_USERNAME/base-api:latest"
echo "  3. Update k8s/*.yaml files with your image names"
echo ""

echo -e "${GREEN}✓ Docker images built${NC}"
echo ""

# Deploy Kubernetes resources
echo "=========================================="
echo "Step 7: Deploying Applications"
echo "=========================================="

echo "Deploying Zabbix monitoring..."
kubectl apply -f k8s/zabbix/

echo "Waiting for Zabbix to be ready (this may take 2-3 minutes)..."
sleep 120

echo "Deploying client applications..."
kubectl apply -f k8s/cliente-a/
kubectl apply -f k8s/cliente-b/
kubectl apply -f k8s/cliente-c/

echo "Deploying monitoring services..."
kubectl apply -f k8s/monitoring/

echo -e "${GREEN}✓ Applications deployed${NC}"
echo ""

# Wait for pods
echo "Waiting for pods to be ready..."
sleep 60

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
echo "  kubectl get hpa -A"
echo ""
echo "Access Zabbix:"
echo "  kubectl port-forward -n monitoring svc/zabbix-frontend 8080:80"
echo "  Then open: http://localhost:8080"
echo "  Login: Admin / zabbix"
echo ""
echo "To destroy everything:"
echo "  cd terraform/environments/dev"
echo "  kubectl delete pvc --all -n cliente-a"
echo "  kubectl delete pvc --all -n cliente-b"
echo "  kubectl delete pvc --all -n cliente-c"
echo "  kubectl delete pvc --all -n monitoring"
echo "  terraform destroy -auto-approve"
echo ""
