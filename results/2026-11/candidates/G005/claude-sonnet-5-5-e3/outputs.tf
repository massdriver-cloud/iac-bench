output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Cluster resource ID."
  value       = google_container_cluster.this.id
}

output "endpoint" {
  description = "Kubernetes API endpoint."
  value       = var.enable_private_endpoint ? google_container_cluster.this.private_cluster_config[0].private_endpoint : google_container_cluster.this.endpoint
}

output "ca_certificate" {
  description = "Base64 cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool; bind KSAs with serviceAccount:<pool>[namespace/ksa]."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account" {
  description = "Email of the node service account."
  value       = google_service_account.nodes.email
}
