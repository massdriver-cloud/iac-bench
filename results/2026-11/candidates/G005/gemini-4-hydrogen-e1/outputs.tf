output "cluster_id" {
  description = "Fully qualified GCP resource ID of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "GCP region where the regional GKE cluster is deployed."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Kubernetes API server endpoint IP address."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the cluster."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
}

output "workload_identity_pool" {
  description = "Workload Identity pool used by product-team Kubernetes ServiceAccounts to access GCP services."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Email address of the dedicated least-privilege GCP service account attached to cluster nodes."
  value       = google_service_account.nodes.email
}

output "vpc_name" {
  description = "Name of the shared VPC attached to the cluster."
  value       = local.vpc_name
}

output "subnet_name" {
  description = "Name of the pre-provisioned GKE subnet used by the cluster."
  value       = local.subnet_name
}

output "node_pools" {
  description = "Map of managed node pool names to their GCP resource IDs."
  value = {
    for name, pool in google_container_node_pool.pools :
    name => pool.id
  }
}

output "get_credentials_command" {
  description = "gcloud command to configure kubectl access to this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}
