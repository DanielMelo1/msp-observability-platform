# Namespaces Module - Kubernetes Namespace Management
# Creates namespaces with resource quotas for multi-tenant isolation

# Kubernetes Namespaces
# Each client gets dedicated namespace for resource isolation
resource "kubernetes_namespace" "namespaces" {
  for_each = { for ns in var.namespaces : ns.name => ns }

  metadata {
    name = each.value.name

    labels = merge(
      each.value.labels,
      {
        name    = each.value.name
        managed = "terraform"
      }
    )
  }
}

# Resource Quotas
# Prevent any single client from consuming all cluster resources
resource "kubernetes_resource_quota" "quota" {
  for_each = { for ns in var.namespaces : ns.name => ns }

  metadata {
    name      = "${each.value.name}-quota"
    namespace = kubernetes_namespace.namespaces[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = each.value.resource_quota.cpu_requests
      "limits.cpu"      = each.value.resource_quota.cpu_limits
      "requests.memory" = each.value.resource_quota.memory_requests
      "limits.memory"   = each.value.resource_quota.memory_limits
      "pods"            = each.value.resource_quota.pods
    }
  }
}

# Limit Range
# Sets default resource limits for pods without explicit limits
resource "kubernetes_limit_range" "limit_range" {
  for_each = { for ns in var.namespaces : ns.name => ns }

  metadata {
    name      = "${each.value.name}-limit-range"
    namespace = kubernetes_namespace.namespaces[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"

      # Default limits if not specified in pod spec
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }

      # Default requests if not specified in pod spec
      default_request = {
        cpu    = "200m"
        memory = "256Mi"
      }

      # Maximum allowed
      max = {
        cpu    = "2000m"
        memory = "2Gi"
      }

      # Minimum required
      min = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# Network Policy - Default Deny All
# Security baseline: deny all traffic by default, explicitly allow what's needed
resource "kubernetes_network_policy" "default_deny" {
  for_each = { for ns in var.namespaces : ns.name => ns }

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.namespaces[each.key].metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]
  }
}

# Network Policy - Allow Monitoring
# Explicitly allow Zabbix agents to collect metrics
resource "kubernetes_network_policy" "allow_monitoring" {
  for_each = { for ns in var.namespaces : ns.name => ns if ns.name != "monitoring" }

  metadata {
    name      = "allow-zabbix-monitoring"
    namespace = kubernetes_namespace.namespaces[each.key].metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress"]

    # Allow traffic from monitoring namespace (Zabbix agents)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "10050" # Zabbix agent port
      }
    }
  }
}

# Network Policy - Allow DNS
# All pods need DNS resolution
resource "kubernetes_network_policy" "allow_dns" {
  for_each = { for ns in var.namespaces : ns.name => ns }

  metadata {
    name      = "allow-dns"
    namespace = kubernetes_namespace.namespaces[each.key].metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Egress"]

    # Allow DNS queries to kube-dns
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }
}
