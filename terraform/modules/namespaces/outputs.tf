# Namespaces Module Outputs

output "namespace_names" {
  description = "List of created namespace names"
  value       = [for ns in kubernetes_namespace.namespaces : ns.metadata[0].name]
}

output "namespace_ids" {
  description = "Map of namespace names to IDs"
  value       = { for ns in kubernetes_namespace.namespaces : ns.metadata[0].name => ns.id }
}
