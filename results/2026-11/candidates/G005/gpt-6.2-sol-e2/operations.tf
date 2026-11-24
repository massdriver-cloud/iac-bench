variable "deletion_protection" {
  description = "Keep enabled for live clusters. To intentionally retire a cluster, apply with this set to false before destroying it."
  type        = bool
  default     = true
  nullable    = false
}

output "cluster_id" {
  description = "Fully qualified GKE cluster resource ID."
  value       = google_container_cluster.this.id
}

output "cluster_dns_endpoint" {
  description = "IAM-authenticated DNS hostname of the Kubernetes API."
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "get_credentials_command" {
  description = "Command to configure kubectl for the DNS endpoint using the caller's Google Cloud identity."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id} --dns-endpoint"
}

output "node_pool_name" {
  description = "Name of the managed general-purpose node pool."
  value       = google_container_node_pool.general.name
}

output "node_service_account_email" {
  description = "IAM identity of the nodes (not the identity of product workloads)."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool used for Kubernetes service account principals."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}
