# Deployment Guide

## Prerequisites

**Required Tools:**
```bash
# Verify installations
terraform --version  # >= 1.9
kubectl version      # >= 1.31
aws --version        # >= 2.0
docker --version     # >= 20.0
helm version         # >= 3.0
```

**AWS Configuration:**
```bash
# Configure AWS CLI
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-east-1)

# Verify access
aws sts get-caller-identity
```

---

## Step 1: Deploy Infrastructure

**Provision AWS resources (VPC, EKS, nodes):**
```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Review plan
terraform plan

# Apply (takes ~15 minutes)
terraform apply -auto-approve

# Save outputs
terraform output -json > outputs.json
```

**Expected resources created:**
- VPC with 6 subnets
- EKS cluster
- 3 EC2 nodes (t3.medium)
- Security groups
- IAM roles

---

## Step 2: Configure kubectl
```bash
# Get EKS cluster credentials
aws eks update-kubeconfig --region us-east-1 --name msp-observability-cluster

# Verify connection
kubectl get nodes
# Should show 3 nodes in Ready state
```

---

## Step 3: Install AWS Load Balancer Controller
```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get cluster name from Terraform output
CLUSTER_NAME=$(terraform output -raw cluster_name)

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

---

## Step 4: Deploy Applications

**Deploy Zabbix monitoring:**
```bash
# Create monitoring namespace and Zabbix stack
kubectl apply -f k8s/zabbix/

# Wait for pods to be ready (~3 minutes)
kubectl wait --for=condition=ready pod -l app=zabbix-server -n monitoring --timeout=300s

# Get Zabbix URL
kubectl get ingress -n monitoring
```

**Deploy client applications:**
```bash
# Deploy all clients
kubectl apply -f k8s/cliente-a/
kubectl apply -f k8s/cliente-b/
kubectl apply -f k8s/cliente-c/

# Deploy webhook handler
kubectl apply -f k8s/monitoring/webhook-handler.yaml

# Verify all pods running
kubectl get pods -A
```

---

## Step 5: Configure Ingress

**Create Ingress resources:**
```bash
# Apply Ingress configurations
kubectl apply -f k8s/ingress.yaml

# Wait for ALB provisioning (~2 minutes)
kubectl get ingress -A --watch

# Get ALB DNS name
ALB_DNS=$(kubectl get ingress cliente-a-ingress -n cliente-a -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $ALB_DNS
```

**Configure local DNS (for testing):**
```bash
# Get ALB IP
ALB_IP=$(dig +short $ALB_DNS | head -n1)

# Add to /etc/hosts
sudo bash -c "cat >> /etc/hosts << EOF
$ALB_IP cliente-a.msp-demo.local
$ALB_IP cliente-b.msp-demo.local
$ALB_IP cliente-c.msp-demo.local
$ALB_IP zabbix.msp-demo.local
EOF"
```

---

## Step 6: Configure Zabbix

**Import monitoring templates:**
```bash
cd zabbix-config/scripts

# Import templates
./import-templates.sh

# Configure hosts
python3 configure-hosts.py

# Import dashboards
./setup-dashboards.sh
```

**Access Zabbix:**
```
URL: http://zabbix.msp-demo.local
Username: Admin
Password: zabbix

First login:
1. Change default password
2. Verify templates imported
3. Check hosts discovered
4. Review dashboards
```

---

## Step 7: Deploy Automation

**Configure webhook handler:**
```bash
# Create Slack webhook secret
kubectl create secret generic slack-credentials \
  --from-literal=webhook-url=https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  -n monitoring

# Verify webhook handler running
kubectl get pods -n monitoring -l app=webhook-handler
```

**Test auto-scaling:**
```bash
# Generate load on Cliente A
kubectl run load-generator --image=busybox --restart=Never -n cliente-a \
  -- /bin/sh -c "while true; do wget -q -O- http://cliente-a-api:8000/api/items; done"

# Watch scaling
kubectl get hpa -n cliente-a --watch
kubectl get pods -n cliente-a --watch

# Cleanup
kubectl delete pod load-generator -n cliente-a
```

---

## Verification Checklist

**Infrastructure:**
```bash
✓ kubectl get nodes           # 3 nodes Ready
✓ kubectl get ns              # All namespaces created
✓ kubectl get ingress -A      # ALB address assigned
```

**Applications:**
```bash
✓ kubectl get pods -n cliente-a    # 2 pods Running
✓ kubectl get pods -n cliente-b    # 5 pods Running
✓ kubectl get pods -n cliente-c    # 1 pod Running
✓ kubectl get pods -n monitoring   # All pods Running
```

**Monitoring:**
```bash
✓ Access http://zabbix.msp-demo.local
✓ Zabbix shows all hosts
✓ Dashboards display metrics
```

**Access Endpoints:**
```bash
# Test all services
curl http://cliente-a.msp-demo.local/health
curl http://cliente-b.msp-demo.local/health
curl http://cliente-c.msp-demo.local/health
```

---

## Common Issues

**kubectl can't connect:**
```bash
aws eks update-kubeconfig --region us-east-1 --name msp-observability-cluster
```

**Pods stuck in Pending:**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Check: Insufficient CPU/memory, node not ready
```

**Ingress no address:**
```bash
# Check Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Can't access via hostname:**
```bash
# Verify /etc/hosts entry
cat /etc/hosts | grep msp-demo

# Test with ALB DNS directly
curl http://$ALB_DNS/health -H "Host: cliente-a.msp-demo.local"
```

---

## Cleanup

**Destroy all resources:**
```bash
# Delete Kubernetes resources first
kubectl delete -f k8s/ --all-namespaces

# Wait for Load Balancer deletion (~2 minutes)
sleep 120

# Destroy infrastructure
cd terraform/environments/dev
terraform destroy -auto-approve
```

**Estimated costs if left running:**
- ~$8/day
- ~$240/month

---

## Next Steps

- [Run demonstration](DEMO.md)
- [View troubleshooting guide](TROUBLESHOOTING.md)
- Configure Slack notifications
- Set up automated backups

---

**Deployment time:** ~30 minutes
**Last Updated:** December 2025
