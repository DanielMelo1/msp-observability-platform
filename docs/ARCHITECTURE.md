# Technical Architecture

## System Overview

Multi-tenant Zabbix monitoring platform running on AWS EKS, designed for MSPs managing multiple clients with different SLA requirements.
```
┌──────────────────────────────────────────────────────┐
│                    Internet                          │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│          Application Load Balancer (ALB)             │
│          (Routes traffic by hostname)                │
└───────────────────────┬──────────────────────────────┘
                        │
         ┌──────────────┼──────────────┐
         ▼              ▼              ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │Cliente  │    │Cliente  │    │Cliente  │
    │   A     │    │   B     │    │   C     │
    │Namespace│    │Namespace│    │Namespace│
    └─────────┘    └─────────┘    └─────────┘
         │              │              │
         └──────────────┴──────────────┘
                        │
                        ▼
            ┌───────────────────────┐
            │   Zabbix Monitoring   │
            │   (Central Platform)  │
            └───────────────────────┘
```

---

## Infrastructure Components

### AWS Resources

**VPC Configuration:**
- CIDR: 10.0.0.0/16
- 3 Public Subnets (ALB, NAT Gateway)
- 3 Private Subnets (EKS nodes)
- Internet Gateway + NAT Gateway

**EKS Cluster:**
- Kubernetes: 1.31
- Node Type: t3.medium (2 vCPU, 4 GiB RAM)
- Node Count: 3 (min 2, max 5)
- Managed by Terraform

**Networking:**
- Single ALB for all services (~$16/month)
- AWS Load Balancer Controller (manages ALB)
- Ingress resources for routing

---

## Application Architecture

### Client Isolation

Each client runs in dedicated namespace:

**Cliente A (E-commerce):**
- SLA: 99%
- Pods: 2-8 (auto-scaling)
- Trigger: CPU > 75% for 5min

**Cliente B (Fintech):**
- SLA: 99.99%
- Pods: 5-20 (aggressive scaling)
- Trigger: CPU > 60% for 2min

**Cliente C (SaaS):**
- SLA: 99.5%
- Pods: 1-4 (cost-optimized)
- Trigger: CPU > 80% for 10min
- Off-hours: Scale to 1 pod (8pm-8am)

---

## Monitoring Stack

### Zabbix Components
```
monitoring namespace:
├── Zabbix Server (metrics collection)
├── Zabbix Frontend (web UI)
├── PostgreSQL (data storage)
└── Zabbix Agents (DaemonSet on all nodes)
```

### Monitoring Flow
```
1. Apps export metrics → /metrics endpoint
2. Zabbix Agents collect → every 60s
3. Zabbix Server evaluates → triggers
4. Trigger fires → webhook to automation service
5. Auto-scaler executes → kubectl scale
6. Kubernetes scales → new pods
7. Notification sent → Slack
```

---

## Auto-Scaling Logic

### Webhook Handler
```python
# When Zabbix trigger fires
POST /trigger
{
  "namespace": "cliente-a",
  "deployment": "cliente-a-api",
  "current_cpu": 82,
  "threshold": 75
}

# Auto-scaler responds
current_replicas = 2
target_replicas = 3  # Based on scaling policy

kubectl scale deployment cliente-a-api --replicas=3 -n cliente-a
```

### Scaling Policies
```
Cliente A: Conservative (+1 pod, max 8)
Cliente B: Aggressive (+2 pods, max 20)
Cliente C: Cost-focused (+1 pod, max 4)
```

---

## Cost Optimization

### Off-Hours Scaling (Cliente C)
```python
Business Hours (8am-8pm):
  - Allow HPA scaling (1-4 pods)
  
Off-Hours (8pm-8am):
  - Force scale to 1 pod
  - Savings: ~60% compute cost
```

### Resource Efficiency
```
Single ALB vs Multiple Load Balancers:
  - 1 ALB = $16/month
  - 4 separate LBs = $64/month
  - Savings: $48/month
```

---

## Security

### Network Isolation
```yaml
# Default deny all traffic
NetworkPolicy: default-deny-all

# Explicit allow rules:
- Ingress from ALB
- Zabbix monitoring traffic
- Inter-service communication (same namespace only)
```

### RBAC
```
Webhook Handler Service Account:
  - Can scale deployments
  - Can list pods
  - Cannot delete/modify other resources
  - Principle of least privilege
```

---

## Technology Choices

| Component         | Choice    | Why                               |
|-------------------|-----------|-----------------------------------|
| **IaC**           | Terraform | Industry standard, AWS provider   |
| **Orchestration** | EKS       | Managed K8s, less ops burden      |
| **Monitoring**    | Zabbix    | Built-in alerting, mature triggers|
| **Load Balancer** | ALB       | Native AWS, cost-effective        |
| **Language**      | Python    | Fast development, clear syntax    |

---

## Scaling Limits

**Current Capacity (3 nodes):**
- ~1500 requests/second
- ~40-50 pods total

**Maximum Capacity (5 nodes):**
- ~2500 requests/second
- ~60-80 pods total

**To Scale Beyond:**
- Add more nodes (Cluster Autoscaler)
- Multi-cluster setup
- Regional distribution

---

## Performance Targets
```
Latency (P95): < 250ms
Throughput: ~500 req/s per node
Scale-up time: 30-90 seconds
Monitoring interval: 60 seconds
Alert response: < 2 minutes
```

---

## Related Documentation

- [DEPLOYMENT.md](DEPLOYMENT.md) - How to deploy
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues

---

**Last Updated:** December 2025
