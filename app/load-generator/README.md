# Load Generator - Locust

Traffic simulation for MSP clients with different patterns.

## Usage

### Run locally
```bash
pip install -r requirements.txt
locust -f locustfile.py --host http://cliente-a.msp-demo.local
```

Access UI: http://localhost:8089

### Run in Kubernetes
```bash
kubectl run load-generator --image=load-generator:latest -n cliente-a
kubectl port-forward pod/load-generator 8089:8089 -n cliente-a
```

## Test Scenarios

**Cliente A (E-commerce):**
- Users: 100
- Spawn rate: 10/s
- Simulates: Product browsing, orders

**Cliente B (Fintech):**
- Users: 500
- Spawn rate: 50/s
- Simulates: Transactions, balance checks

**Cliente C (SaaS):**
- Users: 50
- Spawn rate: 5/s
- Simulates: CRM operations
