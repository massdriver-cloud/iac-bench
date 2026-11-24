output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Cluster resource ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Cluster location (region)."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control plane endpoint."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64 cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Grant GCP roles (Pub/Sub, GCS, Cloud SQL...) to principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<pool>/subject/ns/<ns>/sa/<ksa> or via a GSA bound to a KSA."
  value       = local.workload_pool
}

output "node_service_account" {
  description = "Email of the node service account."
  value       = google_service_account.nodes.email
}

output "node_pools" {
  description = "Node pool names."
  value       = [for p in google_container_node_pool.pools : p.name]
}

output "get_credentials_command" {
  description = "gcloud command to fetch kubeconfig."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}
