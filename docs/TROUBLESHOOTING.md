# Troubleshooting Guide

## Quick Diagnostics

**Check cluster health:**
```bash
kubectl get nodes
kubectl get pods -A
kubectl get events -A --sort-by='.lastTimestamp'
```

---

## Common Issues

### 1. Terraform Apply Fails

**Error: "Error creating EKS cluster"**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify IAM permissions
aws iam get-user

# Common fix: Increase service quotas
aws service-quotas list-service-quotas \
  --service-code eks \
  --region us-east-1
```

**Error: "LoadBalancer limit reached"**
```bash
# This was the issue in your previous project
# Check current limits
aws service-quotas get-service-quota \
  --service-code elasticloadbalancing \
  --quota-code L-53DA6B97 \
  --region us-east-1

# Request increase if needed
aws service-quotas request-service-quota-increase \
  --service-code elasticloadbalancing \
  --quota-code L-53DA6B97 \
  --desired-value 50
```

---

### 2. Pods Not Starting

**Pods stuck in Pending:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# - Insufficient CPU/memory → Add nodes
# - ImagePullBackOff → Check image name
# - Node not ready → Check node status
```

**Fix: Scale nodes**
```bash
# Edit node group in Terraform
desired_size = 5  # Increase from 3

terraform apply
```

**Pods stuck in CrashLoopBackOff:**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace>

# Common causes:
# - Missing environment variables
# - Database connection failed
# - Application error

# Check pod configuration
kubectl get pod <pod-name> -n <namespace> -o yaml
```

---

### 3. Ingress/ALB Issues

**Ingress has no address:**
```bash
# Check AWS LB Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Common issues:
# - Controller not installed
# - IAM role missing permissions
# - Subnet tagging incorrect
```

**Fix: Verify subnet tags**
```bash
# Public subnets need these tags:
kubernetes.io/role/elb = 1
kubernetes.io/cluster/<cluster-name> = shared
```

**Can't access application via hostname:**
```bash
# Test with ALB DNS directly
ALB_DNS=$(kubectl get ingress -n cliente-a -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB_DNS/health -H "Host: cliente-a.msp-demo.local"

# If works: DNS issue
# If doesn't work: ALB routing issue
```

---

### 4. Zabbix Issues

**Can't access Zabbix UI:**
```bash
# Check Zabbix pods
kubectl get pods -n monitoring

# Check Zabbix logs
kubectl logs -n monitoring -l app=zabbix-server

# Check database connection
kubectl logs -n monitoring -l app=postgres
```

**Zabbix not collecting metrics:**
```bash
# Check Zabbix Agents running
kubectl get pods -n monitoring -l app=zabbix-agent

# Check agent logs
kubectl logs -n monitoring <zabbix-agent-pod>

# Verify firewall rules
kubectl get networkpolicy -A
```

---

### 5. Auto-Scaling Not Working

**HPA shows "unknown" metrics:**
```bash
# Check metrics server
kubectl get deployment metrics-server -n kube-system

# Install if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Webhook handler not receiving triggers:**
```bash
# Check webhook handler logs
kubectl logs -n monitoring -l app=webhook-handler

# Test webhook manually
kubectl exec -it -n monitoring <webhook-handler-pod> -- curl -X POST http://localhost:8080/trigger \
  -H "Content-Type: application/json" \
  -d '{"namespace":"cliente-a","deployment":"cliente-a-api"}'
```

**Pods not scaling despite high CPU:**
```bash
# Check HPA status
kubectl get hpa -n cliente-a
kubectl describe hpa cliente-a-hpa -n cliente-a

# Check current metrics
kubectl top pods -n cliente-a

# Verify RBAC permissions
kubectl auth can-i update deployments/scale -n cliente-a --as=system:serviceaccount:monitoring:webhook-handler
```

---

### 6. Database Connection Errors

**Application can't connect to database:**
```bash
# Check database pod
kubectl get pods -n cliente-a -l app=postgres

# Check database logs
kubectl logs -n cliente-a <postgres-pod>

# Test connection from app pod
kubectl exec -it -n cliente-a <app-pod> -- \
  psql -h postgres -U postgres -d clientedb
```

**Fix: Reset database credentials**
```bash
kubectl delete secret database-credentials -n cliente-a
kubectl create secret generic database-credentials \
  --from-literal=username=postgres \
  --from-literal=password=newpassword \
  -n cliente-a

# Restart application pods
kubectl rollout restart deployment/cliente-a-api -n cliente-a
```

---

### 7. High AWS Costs

**Unexpected bill:**
```bash
# Check running resources
aws ec2 describe-instances --region us-east-1
aws elbv2 describe-load-balancers --region us-east-1
aws eks list-clusters --region us-east-1

# Common culprits:
# - Forgot to run terraform destroy
# - NAT Gateway running ($32/month)
# - Load Balancer not deleted
```

**Fix: Immediate shutdown**
```bash
# Delete Kubernetes resources
kubectl delete -f k8s/ --all-namespaces

# Wait for LB deletion
sleep 120

# Destroy infrastructure
terraform destroy -auto-approve
```

---

## Debug Commands Reference

**Check resource usage:**
```bash
kubectl top nodes
kubectl top pods -n <namespace>
```

**View logs:**
```bash
# Recent logs
kubectl logs <pod-name> -n <namespace>

# Follow logs
kubectl logs -f <pod-name> -n <namespace>

# Previous container logs
kubectl logs <pod-name> -n <namespace> --previous
```

**Execute commands in pod:**
```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
```

**Port forward for local testing:**
```bash
kubectl port-forward -n <namespace> svc/<service-name> 8080:8000
# Access: http://localhost:8080
```

**Check events:**
```bash
# All events
kubectl get events -A --sort-by='.lastTimestamp'

# Namespace events
kubectl get events -n <namespace>
```

---

## Getting Help

**Export cluster state:**
```bash
# Useful for sharing with support
kubectl cluster-info dump > cluster-dump.txt
```

**Check Terraform state:**
```bash
terraform show
terraform state list
```

**AWS Console:**
- EKS: Check cluster status, node groups
- EC2: Verify instances running
- VPC: Check subnets, route tables
- CloudWatch: View logs if enabled

---

## Prevention Tips

1. **Always run in dev/test first**
2. **Set up billing alerts** ($50, $100, $200 thresholds)
3. **Tag all resources** (Owner, Environment, Project)
4. **Use `terraform plan`** before apply
5. **Clean up after demos** (terraform destroy)

---

**Need more help?** Check:
- [Deployment guide](DEPLOYMENT.md)
- [Architecture docs](ARCHITECTURE.md)
- AWS documentation
- Kubernetes documentation

---

**Last Updated:** December 2025
