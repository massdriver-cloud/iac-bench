output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind teams' Google service accounts to Kubernetes service accounts through this pool."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Email of the node service account."
  value       = google_service_account.nodes.email
}

output "node_pool_names" {
  description = "Names of the node pools created by this module."
  value       = [for k, p in google_container_node_pool.this : p.name]
}

output "network_self_link" {
  description = "Self link of the VPC the cluster runs in (read from the network team's apps-<environment> VPC)."
  value       = data.google_compute_network.vpc.self_link
}

output "subnetwork_self_link" {
  description = "Self link of the GKE subnet the cluster uses."
  value       = data.google_compute_subnetwork.gke.self_link
}
