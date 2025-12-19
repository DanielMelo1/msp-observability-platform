# CI/CD Pipelines

This project uses GitHub Actions for continuous integration and deployment.

## Workflows

### 1. Validate (`validate.yaml`)
**Triggers:** Pull requests and pushes to main

**Steps:**
- Terraform format check and validation
- Kubernetes manifests validation (dry-run)
- Python code linting (flake8)
- Docker build tests
- Security scanning (Trivy)

**Purpose:** Ensure code quality before merging

### 2. Build and Push (`build-and-push.yaml`)
**Triggers:** Pushes to main, tags, manual dispatch

**Steps:**
- Build Docker images for:
  - base-api
  - webhook-handler
  - load-generator
- Push to GitHub Container Registry (ghcr.io)
- Tag with git SHA and semantic versions

**Purpose:** Automated image building and registry management

### 3. Deploy (`deploy.yaml`)
**Triggers:** Manual dispatch only
**Status:** Template (commented)

**When enabled:**
- Terraform apply to AWS
- Deploy applications to EKS
- Verify deployments

**Purpose:** Automated infrastructure and application deployment

## Setup

### Enable Docker Image Builds
No setup required - uses `GITHUB_TOKEN` automatically.

### Enable Deploy Workflow
1. Uncomment jobs in `deploy.yaml`
2. Add GitHub Secrets:
```
   AWS_ACCESS_KEY_ID
   AWS_SECRET_ACCESS_KEY
```
3. Configure GitHub Environments (Settings → Environments)
4. Update cluster name in workflow

## Pipeline Architecture
```
┌─────────────┐
│   PR/Push   │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   Validate          │
│   - Terraform       │
│   - Kubernetes      │
│   - Python          │
│   - Docker Build    │
│   - Security Scan   │
└──────┬──────────────┘
       │
       ▼ (on main)
┌─────────────────────┐
│   Build & Push      │
│   - Build images    │
│   - Push to GHCR    │
│   - Tag versions    │
└──────┬──────────────┘
       │
       ▼ (manual)
┌─────────────────────┐
│   Deploy            │
│   - Terraform apply │
│   - kubectl apply   │
│   - Verify          │
└─────────────────────┘
```

## Best Practices

- All PRs must pass validation
- Images tagged with git SHA for traceability
- Deploy workflow requires manual approval
- Secrets never committed to repository
- Infrastructure changes require plan review

## Monitoring

View workflow runs: Actions tab in GitHub repository

## Future Enhancements

- [ ] Automated testing (unit, integration)
- [ ] Deployment rollback automation
- [ ] Slack/Teams notifications
- [ ] Multi-environment support (dev/staging/prod)
- [ ] Terraform state locking with DynamoDB
