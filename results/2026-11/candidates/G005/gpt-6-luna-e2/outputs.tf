output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region hosting the regional GKE cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Public Kubernetes API endpoint; access is limited by master authorized networks."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool for Kubernetes service accounts in this cluster."
  value       = local.workload_pool
}

output "node_service_account_email" {
  description = "Service account attached to GKE worker nodes."
  value       = google_service_account.nodes.email
}
