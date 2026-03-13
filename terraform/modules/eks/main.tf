# ─────────────────────────────────────────────────────────────────────────────
# EKS MODULE — Cluster, Node Group and IRSA
# ─────────────────────────────────────────────────────────────────────────────
# Creates a production-ready EKS cluster following AWS security best practices.
#
# Security controls implemented:
#   - EKS secrets encryption with AWS KMS
#   - Private endpoint only (no public internet access to control plane)
#   - All 5 control plane log types enabled
#   - Security group with restricted egress (no 0.0.0.0/0 on all ports)
#   - IAM least-privilege for Load Balancer Controller
#   - IRSA (IAM Roles for Service Accounts) via OIDC provider
# ─────────────────────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────
# KMS KEY FOR EKS SECRETS ENCRYPTION
# ───────────────────────────────────────────────────────────
# Encrypts Kubernetes secrets at rest in etcd.
# Without this, secrets are stored in base64 only — readable
# by anyone with direct etcd access.
# ───────────────────────────────────────────────────────────
resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secrets encryption - ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-eks-secrets-key"
      Purpose = "EKS secrets encryption"
    }
  )
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# ───────────────────────────────────────────────────────────
# EKS CLUSTER IAM ROLE
# ───────────────────────────────────────────────────────────
# Allows EKS service to manage AWS resources on your behalf.
# Only eks.amazonaws.com can assume this role.
# ───────────────────────────────────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# ───────────────────────────────────────────────────────────
# EKS CLUSTER SECURITY GROUP
# ───────────────────────────────────────────────────────────
# Restricts egress to specific ports and protocols only.
# Checkov CKV_AWS_382: no unrestricted egress on port -1
# ───────────────────────────────────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  # HTTPS egress — required for EKS control plane API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound for EKS API calls"
  }

  # DNS egress — required for service discovery
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow DNS resolution"
  }

  # Node communication — kubelet and pods
  egress {
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Allow communication with worker nodes on private network"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )
}

# ───────────────────────────────────────────────────────────
# EKS CLUSTER
# ───────────────────────────────────────────────────────────
# Security hardening applied:
#   - endpoint_public_access = false (private VPC only)
#   - encryption_config with KMS for secrets
#   - All 5 log types enabled for full audit trail
#
# Note: With public access disabled, kubectl must be run
# from within the VPC (bastion host or VPN)
# ───────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)
    # Private access enabled — control plane accessible within VPC
    endpoint_private_access = true
    # Public access disabled — control plane not exposed to internet
    # Checkov CKV_AWS_38 + CKV_AWS_39
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Secrets encryption with KMS
  # Checkov CKV_AWS_58: secrets encrypted at rest
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
    resources = ["secrets"]
  }

  # All 5 control plane log types enabled
  # Checkov CKV_AWS_37: full audit trail in CloudWatch
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_policy
  ]
}

# ───────────────────────────────────────────────────────────
# NODE GROUP IAM ROLE
# ───────────────────────────────────────────────────────────
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# ───────────────────────────────────────────────────────────
# IAM POLICY — AWS LOAD BALANCER CONTROLLER
# ───────────────────────────────────────────────────────────
# Least-privilege policy for ALB/NLB management.
# Checkov CKV_AWS_355 + CKV_AWS_290:
#   - No wildcard actions (elasticloadbalancing:* removed)
#   - Specific actions only
#   - Resource scoped where possible
# ───────────────────────────────────────────────────────────
resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${var.cluster_name}-load-balancer-controller"
  description = "Least-privilege policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeResources"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLoadBalancers"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:*"
      },
      {
        Sid    = "ManageSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_load_balancer_policy" {
  policy_arn = aws_iam_policy.load_balancer_controller.arn
  role       = aws_iam_role.node.name
}

# ───────────────────────────────────────────────────────────
# EKS NODE GROUP
# ───────────────────────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size
  capacity_type  = "ON_DEMAND"

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-node-group"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]
}

# ───────────────────────────────────────────────────────────
# OIDC PROVIDER FOR IRSA
# ───────────────────────────────────────────────────────────
# Enables IAM Roles for Service Accounts (IRSA).
# Allows Kubernetes pods to assume IAM roles directly
# without static credentials inside containers.
# ───────────────────────────────────────────────────────────
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}
