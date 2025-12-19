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

## Prerequisites

### AWS Account Requirements

- AWS Account with appropriate permissions
- AWS CLI configured with credentials
- Permissions needed:
  - EKS: Full access
  - EC2: Full access
  - VPC: Full access
  - IAM: Create roles and policies
  - EBS: Create and manage volumes

### Required Tools

- Terraform >= 1.0
- kubectl >= 1.28
- AWS CLI >= 2.0
- Helm >= 3.0
- Docker >= 20.0

### AWS EKS Addons

The following addons are automatically configured during deployment:

1. **AWS Load Balancer Controller**: Manages ALB/NLB for Ingress resources
2. **EBS CSI Driver**: Enables dynamic PersistentVolume provisioning with EBS
3. **Metrics Server**: Provides resource metrics for HPA

## Important Notes

### EBS CSI Driver IRSA

The EBS CSI Driver requires IAM Roles for Service Accounts (IRSA) to manage EBS volumes. This is automatically configured in the setup script:

- Creates OIDC provider for the cluster
- Creates IAM role: `AmazonEKS_EBS_CSI_DriverRole`
- Attaches policy: `AmazonEKS_EBS_CSI_Driver_Policy`
- Annotates service account: `ebs-csi-controller-sa`

### PostgreSQL Storage

PostgreSQL uses EBS volumes with the `subPath` configuration to avoid conflicts with the `lost+found` directory that exists in new EBS volumes.

Configuration:
```yaml
volumeMounts:
- name: postgres-storage
  mountPath: /var/lib/postgresql/data
  subPath: pgdata  # Important: avoids lost+found conflict
env:
- name: PGDATA
  value: "/var/lib/postgresql/data/pgdata"
```

### Zabbix Server Resources

The Zabbix Server memory limit is set to 2Gi to comply with the namespace LimitRange:
```yaml
resources:
  limits:
    memory: "2Gi"  # Must be <= namespace limit (2Gi)
    cpu: "1000m"
```

## Troubleshooting

### Issue: Pods stuck in ImagePullBackOff

**Symptom:**
```
cliente-a-api-xxx   0/1   ImagePullBackOff
```

**Cause:** Docker images not accessible

**Solution:**
1. Verify images are public on GHCR
2. Or build and push your own images
3. Update image references in Kubernetes manifests

### Issue: PersistentVolumeClaims stuck in Pending

**Symptom:**
```
postgres-pvc   Pending   gp2
```

**Cause:** EBS CSI Driver not properly configured

**Solution:**
```bash
# Check EBS CSI controller pods
kubectl get pods -n kube-system | grep ebs-csi

# If controllers are CrashLoopBackOff, check IRSA configuration
kubectl logs -n kube-system ebs-csi-controller-xxx -c ebs-plugin

# Verify service account annotation
kubectl describe sa ebs-csi-controller-sa -n kube-system | grep eks.amazonaws.com/role-arn

# Should show: arn:aws:iam::ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole
```

### Issue: HPA shows "unknown" for CPU metrics

**Symptom:**
```
cliente-a-hpa   cpu: <unknown>/75%
```

**Cause:** Metrics Server not installed or not ready

**Solution:**
```bash
# Check metrics-server
kubectl get pods -n kube-system | grep metrics-server

# If not present, install:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait 1-2 minutes, then check again
kubectl top nodes
kubectl top pods -n cliente-a
```

### Issue: PostgreSQL fails to start with "directory not empty"

**Symptom:**
```
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
```

**Cause:** Missing `subPath` configuration in volumeMount

**Solution:**
Already fixed in `k8s/zabbix/01-postgres.yaml`. Ensure you're using the latest version with:
- `subPath: pgdata` in volumeMount
- `PGDATA=/var/lib/postgresql/data/pgdata` environment variable

### Issue: Zabbix Server pod fails to start (memory limit)

**Symptom:**
```
Error creating: pods "zabbix-server-xxx" is forbidden: maximum memory usage per Container is 2Gi, but limit is 4Gi
```

**Cause:** Memory limit exceeds namespace LimitRange

**Solution:**
Already fixed in `k8s/zabbix/02-zabbix-server.yaml`. Memory limit set to 2Gi.

### Issue: Terraform destroy hangs on namespace deletion

**Symptom:**
```
module.namespaces.kubernetes_namespace.namespaces["monitoring"]: Still destroying... [5m0s elapsed]
Error: context deadline exceeded
```

**Cause:** PersistentVolumeClaims with finalizers blocking namespace deletion

**Solution:**
```bash
# 1. Delete PVCs first
kubectl delete pvc --all -n cliente-a --wait=false
kubectl delete pvc --all -n cliente-b --wait=false
kubectl delete pvc --all -n cliente-c --wait=false
kubectl delete pvc --all -n monitoring --wait=false

# 2. If namespaces still stuck, remove from Terraform state
terraform state rm 'module.namespaces.kubernetes_namespace.namespaces["cliente-a"]'
terraform state rm 'module.namespaces.kubernetes_namespace.namespaces["cliente-b"]'
terraform state rm 'module.namespaces.kubernetes_namespace.namespaces["cliente-c"]'
terraform state rm 'module.namespaces.kubernetes_namespace.namespaces["monitoring"]'

# 3. Destroy remaining resources
terraform destroy -auto-approve
```

## Clean Destruction Process

To avoid issues during infrastructure destruction, follow this order:
```bash
# 1. Delete PersistentVolumeClaims (releases EBS volumes)
kubectl delete pvc --all -n cliente-a
kubectl delete pvc --all -n cliente-b
kubectl delete pvc --all -n cliente-c
kubectl delete pvc --all -n monitoring

# 2. Wait for volumes to be released (1 minute)
sleep 60

# 3. Run Terraform destroy
cd terraform/environments/dev
terraform destroy -auto-approve
```

This ensures EBS volumes are properly deleted before the EKS cluster is destroyed, preventing orphaned resources.

## Cost Optimization

Estimated monthly costs (us-east-1):
- EKS Cluster: ~$73/month
- 3x t3.medium nodes: ~$90/month
- NAT Gateways (3): ~$32/month
- Application Load Balancer: ~$16/month
- EBS Volumes (4x 20GB): ~$8/month

**Total: ~$219/month**

To minimize costs during testing:
1. Destroy infrastructure when not in use
2. Use smaller instance types for testing
3. Reduce number of NAT Gateways to 1
4. Consider using t3.small instead of t3.medium

