output "name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "id" {
  description = "Cluster resource ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Cluster location (region)."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Kubernetes API endpoint."
  value       = google_container_cluster.this.endpoint
}

output "ca_certificate" {
  description = "Base64 cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Grant roles to principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<pool>/subject/ns/<namespace>/sa/<ksa> on Pub/Sub, GCS, Cloud SQL, etc."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Service account used by nodes."
  value       = google_service_account.nodes.email
}

output "network" {
  description = "VPC used."
  value       = local.network
}

output "subnetwork" {
  description = "Subnetwork used."
  value       = local.subnetwork
}
