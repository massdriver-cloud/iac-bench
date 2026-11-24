output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Regional location of the GKE cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Private control-plane endpoint address. Reachable only from appropriately connected networks."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool to use when binding Kubernetes service accounts to Google service accounts."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Dedicated Google service account used by GKE nodes. Application workloads should use Workload Identity instead."
  value       = google_service_account.nodes.email
}

output "network_name" {
  description = "VPC network selected for the cluster."
  value       = data.google_compute_network.cluster.name
}

output "subnetwork_name" {
  description = "Existing regional subnet selected for the cluster."
  value       = data.google_compute_subnetwork.cluster.name
}
