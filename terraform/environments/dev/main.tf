# Development Environment Configuration
# Orchestrates all modules to create complete infrastructure

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DevOps Team"
    }
  }
}

# Kubernetes provider configuration
# Uses EKS cluster credentials after cluster is created
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

# Local values for resource naming
locals {
  cluster_name = "${var.project_name}-${var.environment}-cluster"
  vpc_name     = "${var.project_name}-${var.environment}-vpc"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Networking Module
# Creates VPC, subnets, NAT gateways, route tables
module "networking" {
  source = "../../modules/networking"

  vpc_name     = local.vpc_name
  cluster_name = local.cluster_name
  tags         = local.common_tags
}

# EKS Module
# Creates Kubernetes cluster and worker nodes
module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  tags               = local.common_tags

  depends_on = [module.networking]
}

# Namespaces Module
# Creates Kubernetes namespaces with resource quotas
module "namespaces" {
  source = "../../modules/namespaces"

  namespaces = [
    {
      name = "monitoring"
      labels = {
        tier = "infrastructure"
      }
      resource_quota = {
        cpu_requests    = "4"
        cpu_limits      = "8"
        memory_requests = "8Gi"
        memory_limits   = "16Gi"
        pods            = "30"
      }
    },
    {
      name = "cliente-a"
      labels = {
        tier   = "application"
        client = "cliente-a"
        sla    = "99"
      }
      resource_quota = {
        cpu_requests    = "4"
        cpu_limits      = "8"
        memory_requests = "8Gi"
        memory_limits   = "16Gi"
        pods            = "20"
      }
    },
    {
      name = "cliente-b"
      labels = {
        tier   = "application"
        client = "cliente-b"
        sla    = "99.99"
      }
      resource_quota = {
        cpu_requests    = "6"
        cpu_limits      = "12"
        memory_requests = "12Gi"
        memory_limits   = "24Gi"
        pods            = "30"
      }
    },
    {
      name = "cliente-c"
      labels = {
        tier   = "application"
        client = "cliente-c"
        sla    = "99.5"
      }
      resource_quota = {
        cpu_requests    = "2"
        cpu_limits      = "4"
        memory_requests = "4Gi"
        memory_limits   = "8Gi"
        pods            = "10"
      }
    }
  ]

  tags = local.common_tags

  depends_on = [module.eks]
}
