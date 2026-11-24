output "cluster_id" {
  description = "Fully qualified identifier of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "region" {
  description = "Region of the GKE cluster."
  value       = google_container_cluster.this.location
}

output "dns_endpoint" {
  description = "IAM-gated Kubernetes API endpoint."
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "get_credentials_command" {
  description = "Command for configuring kubectl using the DNS endpoint and your Google Cloud identity."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --project=${var.project_id} --region=${var.region} --dns-endpoint"
}

output "node_pool_names" {
  description = "Names of the separately managed node pools."
  value       = { for name, pool in google_container_node_pool.this : name => pool.name }
}

output "node_service_account_email" {
  description = "Dedicated GKE node identity. Grant it repository-level image pull access if needed, not application permissions."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool shared by GKE clusters in this project."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}
