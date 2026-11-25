output "cluster_id" {
  description = "Full resource ID of the GKE Standard cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE Standard cluster."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "GCP region where the regional GKE cluster is deployed."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "IP address of the Kubernetes control plane API endpoint."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the cluster control plane."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool for binding product-team Kubernetes ServiceAccounts to GCP IAM roles (Pub/Sub, Cloud Storage, Cloud SQL, etc.)."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Email address of the dedicated least-privilege service account attached to this cluster's nodes."
  value       = google_service_account.nodes.email
}

output "node_network_tag" {
  description = "Compute Engine network tag applied to every worker node in this cluster."
  value       = local.cluster_node_tag
}

output "vpc_name" {
  description = "Name of the environment VPC attached to this cluster."
  value       = local.vpc_name
}

output "subnet_name" {
  description = "Name of the pre-created regional GKE subnet attached to this cluster."
  value       = local.subnet_name
}

output "node_pool_names" {
  description = "Map of logical node pool keys to their actual GKE node pool names."
  value       = { for k, np in google_container_node_pool.this : k => np.name }
}

output "get_credentials_command" {
  description = "Ready-to-run gcloud command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}
