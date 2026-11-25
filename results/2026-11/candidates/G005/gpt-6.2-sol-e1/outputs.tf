output "cluster_id" {
  description = "Fully qualified GKE cluster resource ID."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "The GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "The cluster's regional location."
  value       = google_container_cluster.this.location
}

output "cluster_dns_endpoint" {
  description = "DNS hostname for IAM-authenticated access to the Kubernetes API."
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "get_credentials_command" {
  description = "Command to configure kubectl for the DNS-only control plane; requires your own Google credentials."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region=${var.region} --project=${var.project_id} --dns-endpoint"
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool for this cluster's Kubernetes service accounts."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Dedicated node identity; use it for node-level grants such as private image pulls, not application privileges."
  value       = google_service_account.nodes.email
}

output "node_pool_names" {
  description = "Names of the separately managed node pools."
  value       = sort(keys(google_container_node_pool.this))
}
