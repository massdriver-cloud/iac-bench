output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}
output "location" {
  description = "Regional control plane location."
  value       = google_container_cluster.this.location
}
output "node_service_account" {
  description = "Grant this principal reader access only on repositories hosting node-pulled private images."
  value       = google_service_account.nodes.email
}
output "workload_pool" {
  description = "Workload Identity Federation pool for application IAM grants."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}
