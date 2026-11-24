output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The IP address of this cluster's Kubernetes master"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "The public certificate that is the root of trust for the cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "The workload identity pool of the cluster"
  value       = google_container_cluster.primary.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "The email of the service account used by the GKE nodes"
  value       = google_service_account.gke_nodes.email
}
