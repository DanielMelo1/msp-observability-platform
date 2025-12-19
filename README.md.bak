# MSP Multi-Tenant Observability Platform

Production-ready Zabbix monitoring solution for Managed Service Providers managing multiple AWS clients with different SLAs, auto-scaling requirements, and cost optimization needs.

---

## Why This Project Exists

### The Real-World Problem

Managed Service Providers (MSPs), face a unique operational challenge when managing cloud infrastructure for multiple clients simultaneously. Each client has:

- **Different SLA requirements** (99%, 99.9%, 99.99%)
- **Different budget constraints** (cost optimization is critical)
- **Different traffic patterns** (24/7 vs business hours only)
- **Different scaling needs** (conservative vs aggressive)

**The Challenge:** How do you provide proactive monitoring, automated scaling, and cost optimization for ALL clients at once, while maintaining SLA compliance and resource isolation?

### The Solution

This project demonstrates a **multi-tenant Zabbix monitoring platform** that addresses these challenges through:

- **Isolated monitoring** with client-specific dashboards and metrics
- **SLA-aware auto-scaling** with different thresholds per client
- **Cost optimization** through off-hours scaling for non-critical workloads
- **Self-healing automation** via webhook-driven Kubernetes scaling
- **Proactive alerting** with Slack integration

### Why This Matters for MSPs

Traditional monitoring solutions treat all clients equally. This platform demonstrates **SLA-aware observability** where:

- **Fintech client (99.99% SLA)** → Aggressive auto-scaling at 60% CPU for 2 minutes
- **E-commerce (99% SLA)** → Balanced scaling at 75% CPU for 5 minutes
- **SaaS B2B (99.5% SLA)** → Cost-optimized scaling with off-hours pod reduction

---

## Architecture Overview
```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS EKS Cluster                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Zabbix Namespace                       │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐   │   │
│  │  │   Zabbix     │  │   Zabbix     │  │  PostgreSQL   │   │   │
│  │  │   Server     │←→│   Frontend   │  │  (Database)   │   │   │
│  │  └──────┬───────┘  └──────────────┘  └───────────────┘   │   │
│  │         │                                                │   │
│  │         │ Collects Metrics                               │   │
│  │         ↓                                                │   │
│  │  ┌──────────────────────────────────────────────────┐    │   │
│  │  │        Zabbix Agents (DaemonSet)                 │    │   │
│  │  │        Running on all K8s nodes                  │    │   │
│  │  └──────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Cliente A Namespace (E-commerce)            │   │
│  │  SLA: 99% | Pods: 2-8 | Threshold: 75% CPU / 5min        │   │
│  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐        │   │
│  │  │ FastAPI    │  │ FastAPI    │  │  PostgreSQL  │        │   │
│  │  │ Pod 1      │  │ Pod 2      │  │  Database    │        │   │
│  │  └────────────┘  └────────────┘  └──────────────┘        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Cliente B Namespace (Fintech)               │   │
│  │  SLA: 99.99% | Pods: 5-20 | Threshold: 60% CPU / 2min    │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ...     │   │
│  │  │ FastAPI    │  │ FastAPI    │  │ FastAPI    │          │   │
│  │  │ Pod 1      │  │ Pod 2      │  │ Pod 3      │          │   │
│  │  └────────────┘  └────────────┘  └────────────┘          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Cliente C Namespace (SaaS)                  │   │
│  │  SLA: 99.5% | Pods: 1-4 | Cost Optimization Enabled      │   │
│  │  ┌────────────┐  ┌────────────┐                          │   │
│  │  │ FastAPI    │  │ FastAPI    │  Off-hours: scale to 1   │   │
│  │  │ Pod 1      │  │ Pod 2      │                          │   │
│  │  └────────────┘  └────────────┘                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Monitoring Namespace                        │   │
│  │  ┌────────────────────────────────────────────────┐      │   │
│  │  │  Webhook Handler (receives Zabbix triggers)    │      │   │
│  │  │  → Auto-scaler (kubectl scale deployment)      │      │   │
│  │  │  → Cost Optimizer (off-hours scaling)          │      │   │
│  │  │  → Slack Notifier (alerts)                     │      │   │
│  │  └────────────────────────────────────────────────┘      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow
```
1. Application generates metrics (CPU, memory, response time)
   ↓
2. Zabbix Agent (DaemonSet) collects metrics from pods
   ↓
3. Zabbix Server analyzes metrics against SLA-specific triggers
   ↓
4. Trigger activated (e.g., "Cliente B CPU > 60% for 2min")
   ↓
5. Zabbix fires Action → Webhook to monitoring service
   ↓
6. Webhook Handler receives trigger payload
   ↓
7. Auto-scaler executes: kubectl scale deployment --replicas=X
   ↓
8. Kubernetes scales pods (e.g., 5 → 20 pods for Cliente B)
   ↓
9. Load distributed, CPU normalizes
   ↓
10. Slack notification sent: "Cliente B auto-scaled 5→20 pods"
```

---

## Quick Start

### Prerequisites

- AWS Account with EKS permissions
- Terraform >= 1.9
- kubectl >= 1.31
- AWS CLI configured
- Docker (for local testing)

### Deploy Complete Platform
```bash
# 1. Deploy infrastructure (VPC, EKS, namespaces)
./scripts/setup.sh

# 2. Deploy applications and Zabbix monitoring
./scripts/deploy.sh

# 3. Run demonstration (load test + watch auto-scaling)
./scripts/demo.sh
```

### Access Zabbix Dashboard
```bash
# Get Zabbix URL
kubectl get svc -n zabbix zabbix-frontend

# Default credentials
Username: Admin
Password: zabbix
```

---

## Simulated Clients

| Client | Type | SLA | Traffic Pattern | Auto-scaling | Threshold |
|--------|------|-----|----------------|--------------|-----------|
| **Cliente A** | E-commerce | 99% | 100 → 1500 req/s | 2 → 8 pods | 75% CPU / 5min |
| **Cliente B** | Fintech | 99.99% | 500 → 5000 req/s | 5 → 20 pods | 60% CPU / 2min |
| **Cliente C** | SaaS B2B | 99.5% | 200 → 10 req/s | 1 → 4 pods | 80% CPU / 10min |

### Key Differences

**Cliente A (E-commerce):**
- Moderate SLA (7.2h downtime/month allowed)
- Balanced auto-scaling approach
- No special cost optimization

**Cliente B (Fintech):**
- Critical SLA (4min downtime/month only)
- Aggressive auto-scaling (scales faster, more pods)
- Higher minimum replicas (5 vs 2)
- Shorter evaluation window (2min vs 5min)

**Cliente C (SaaS B2B):**
- Business hours focused (8am-8pm)
- Cost optimization enabled
- Scales down to 1 pod during off-hours (8pm-8am)
- Saves ~60% compute costs during nights/weekends

---

## Project Structure
```
msp-observability-platform/
├── docs/                        # Technical documentation
├── terraform/                   # Infrastructure as Code
│   ├── modules/                 # Reusable Terraform modules
│   └── environments/dev/        # Environment-specific config
├── k8s/                         # Kubernetes manifests
│   ├── zabbix/                  # Monitoring infrastructure
│   ├── cliente-a/               # E-commerce namespace
│   ├── cliente-b/               # Fintech namespace
│   ├── cliente-c/               # SaaS namespace
│   └── monitoring/              # Automation services
├── app/                         # Application code
│   ├── common/                  # Shared configuration
│   ├── base-api/                # FastAPI template
│   └── load-generator/          # Locust load testing
├── zabbix-config/               # Zabbix configuration
│   ├── templates/               # SLA-specific templates
│   ├── dashboards/              # Monitoring dashboards
│   ├── automation/              # Auto-scaling scripts
│   └── scripts/                 # Setup automation
└── scripts/                     # Deployment automation
```

---

## Key Features Demonstrated

### 1. Multi-Tenant Isolation
- Each client runs in dedicated Kubernetes namespace
- Separate resource quotas and limits
- Isolated monitoring templates and dashboards

### 2. SLA-Aware Monitoring
- Different Zabbix triggers per SLA level
- Critical clients (99.99%) get more aggressive thresholds
- Non-critical clients (99%) have relaxed thresholds

### 3. Automated Scaling
- Webhook-driven auto-scaling based on Zabbix triggers
- No manual intervention required
- Scales both up and down based on load

### 4. Cost Optimization
- Cliente C automatically scales down during off-hours
- Saves ~60% compute costs for non-critical workloads
- Scheduling logic in `zabbix-config/automation/cost-optimizer.py`

### 5. Self-Healing
- Failed pods automatically restarted by Kubernetes
- High CPU triggers auto-scaling before incidents
- Proactive monitoring prevents outages

---

## Technology Stack

**Infrastructure:**
- AWS EKS (Kubernetes 1.31)
- Terraform (Infrastructure as Code)
- VPC with public/private subnets

**Monitoring:**
- Zabbix 7.0 (Server + Frontend)
- PostgreSQL 15 (Zabbix database)
- Zabbix Agents (DaemonSet)

**Applications:**
- Python 3.12 + FastAPI
- Gunicorn (production WSGI)
- PostgreSQL (application databases)

**Automation:**
- Python scripts (webhook handlers)
- kubectl (Kubernetes API)
- Slack webhooks (alerting)

**Load Testing:**
- Locust (load generation)
- Scenario-based traffic patterns

**CI/CD:**
- GitHub Actions
- Automated deployment pipelines

---

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[00-WHY-3-CLIENTS.md](docs/00-WHY-3-CLIENTS.md)** - Why this approach is not over-engineering
- **[01-ARCHITECTURE.md](docs/01-ARCHITECTURE.md)** - Detailed technical architecture
- **[02-MSP-CONTEXT.md](docs/02-MSP-CONTEXT.md)** - MSP business context
- **[03-SOLUTION.md](docs/03-SOLUTION.md)** - How this solves MSP challenges
- **[04-DEPLOYMENT.md](docs/04-DEPLOYMENT.md)** - Step-by-step deployment guide
- **[05-DEMO.md](docs/05-DEMO.md)** - Running the demonstration
- **[06-TROUBLESHOOTING.md](docs/06-TROUBLESHOOTING.md)** - Common issues and solutions

---

## FAQ

### Why 3 clients? Isn't that over-engineering?

No. This simulates a real MSP scenario where you manage multiple clients with different requirements. A single-client demo wouldn't demonstrate:
- Multi-tenant isolation (namespaces)
- SLA-specific thresholds
- Differential auto-scaling policies
- Selective cost optimization

The structure is modular - adding a 4th client takes ~10 minutes.

### Why not use Prometheus + Grafana instead of Zabbix?

This project specifically demonstrates Zabbix expertise (required for the role). The architecture patterns would work equally well with Prometheus/Grafana.

### Is this production-ready?

The code quality and architecture are production-ready. For actual production:
- Add proper secrets management (AWS Secrets Manager)
- Implement proper TLS/SSL
- Add network policies
- Implement backup/restore procedures
- Add proper logging aggregation

### How much does this cost to run?

Approximately $150-200/month on AWS:
- EKS cluster: ~$75/month
- 3x t3.medium nodes: ~$90/month
- Load balancers: ~$20/month
- Data transfer: ~$10/month

Use `./scripts/cleanup.sh` to destroy everything when done testing.

---

## Contributing

This is a demonstration project for showcasing technical skills. However, improvements are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Submit a pull request

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Author

**Daniel Melo**
DevOps/SRE Engineer

Created as a technical demonstration project showcasing:
- Multi-tenant Zabbix monitoring
- AWS EKS infrastructure management
- Kubernetes automation
- SLA-aware observability
- Cost optimization strategies

---

## Acknowledgments

This project demonstrates real-world MSP challenges and solutions, inspired by the operational needs of Managed Service Providers managing multiple client infrastructures on AWS.

---

## Frequently Asked Questions

### Why 3 clients instead of just 1?

This demonstrates real MSP operational patterns. A single-client demo cannot show:
- **Multi-tenant isolation** (namespace separation, resource quotas)
- **SLA differentiation** (different thresholds per client criticality)
- **Cost optimization** (selective off-hours scaling)
- **Differential scaling** (aggressive vs conservative policies)

The architecture is modular - adding a 4th client takes ~10 minutes of configuration.

### Is this production-ready?

The code quality and architecture are production-ready. For actual production deployment, add:
- Secrets management (AWS Secrets Manager)
- TLS/SSL certificates (AWS ACM)
- Backup/restore automation
- Network policies enforcement
- Comprehensive logging

### How much does this cost to run?

Approximately $8/day (~$240/month):
- EKS control plane: $73/month
- 3× t3.medium nodes: $90/month
- EBS storage: $6/month
- ALB: $16/month
- NAT Gateway: $32/month
- Data transfer: ~$10/month

Use `terraform destroy` after testing to avoid charges.

### Why Zabbix instead of Prometheus/Grafana?

Zabbix provides built-in alerting and webhook actions without additional components (Alertmanager). For this use case (traditional MSP monitoring with trigger-based automation), Zabbix is simpler and more mature.

