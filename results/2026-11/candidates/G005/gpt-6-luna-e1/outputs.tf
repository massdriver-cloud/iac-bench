output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region hosting the regional cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Private control-plane endpoint address. Access requires private connectivity to the VPC."
  value       = google_container_cluster.this.endpoint
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool for Kubernetes service accounts in this cluster."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Dedicated least-privilege service account used by the node pool. Grant workload access through Workload Identity, not this account."
  value       = google_service_account.nodes.email
}
