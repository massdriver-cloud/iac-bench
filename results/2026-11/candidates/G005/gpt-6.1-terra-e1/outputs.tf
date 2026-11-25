output "cluster_name" {
  value = google_container_cluster.main.name
}

output "cluster_location" {
  value = google_container_cluster.main.location
}

output "cluster_endpoint" {
  description = "Private control-plane IP; reachable only through the VPC or connected networks."
  value       = google_container_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  value = google_service_account.nodes.email
}

output "workload_identity_pool" {
  value = "${var.project_id}.svc.id.goog"
}
