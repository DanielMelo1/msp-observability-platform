# Namespaces Module Variables
# Defines Kubernetes namespaces for multi-tenant isolation

variable "namespaces" {
  description = "List of namespaces to create"
  type = list(object({
    name   = string
    labels = map(string)
    resource_quota = object({
      cpu_requests    = string
      cpu_limits      = string
      memory_requests = string
      memory_limits   = string
      pods            = string
    })
  }))
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
