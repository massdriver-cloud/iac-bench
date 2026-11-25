output "cluster_id" {
  description = "Fully-qualified resource ID of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "IP address/hostname of the Kubernetes API server endpoint."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the cluster."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool for binding Kubernetes ServiceAccounts to GCP IAM roles (Pub/Sub, GCS, Cloud SQL)."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Email address of the dedicated least-privilege service account used by GKE nodes."
  value       = google_service_account.gke_nodes.email
}

output "vpc_name" {
  description = "Name of the VPC used by the cluster."
  value       = local.vpc_name
}

output "subnetwork_name" {
  description = "Name of the regional GKE subnetwork used by the cluster."
  value       = local.subnet_name
}

output "node_pool_names" {
  description = "Names of the managed node pools created in the cluster."
  value       = [for k, pool in google_container_node_pool.pools : pool.name]
}
