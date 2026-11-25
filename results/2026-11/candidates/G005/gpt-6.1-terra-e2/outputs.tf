output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Regional cluster location."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control plane endpoint IP. Reachability depends on private_endpoint and authorized networks."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded Kubernetes API CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  description = "Service account used by GKE nodes, not by workloads."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this project."
  value       = "${var.project_id}.svc.id.goog"
}

output "network" {
  description = "Existing network and subnetwork used by this cluster."
  value = {
    network    = local.network
    subnetwork = local.subnetwork
  }
}
