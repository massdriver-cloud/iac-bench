output "cluster_id" {
  description = "Cluster resource ID."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Cluster name, for gcloud container clusters get-credentials."
  value       = google_container_cluster.this.name
}

output "dns_endpoint" {
  description = "IAM-authenticated DNS endpoint of the control plane."
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "workload_pool" {
  description = "Workload Identity pool; grant Google Cloud roles to principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<pool>/subject/ns/<namespace>/sa/<ksa>."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  description = "Service account the nodes run as."
  value       = google_service_account.nodes.email
}
