output "cluster_name" {
  value       = google_container_cluster.this.name
  description = "Cluster name."
}

output "region" {
  value       = google_container_cluster.this.location
  description = "Regional cluster location."
}

output "endpoint" {
  value       = google_container_cluster.this.endpoint
  description = "Kubernetes API endpoint; access is restricted to authorized CIDRs."
  sensitive   = true
}

output "cluster_ca_certificate" {
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  description = "Base64-encoded Kubernetes API CA certificate."
  sensitive   = true
}

output "workload_identity_pool" {
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
  description = "Workload Identity Federation pool for workload IAM bindings."
}

output "node_service_account" {
  value       = google_service_account.nodes.email
  description = "Least-privilege node service account; do not grant workload permissions to it."
}
