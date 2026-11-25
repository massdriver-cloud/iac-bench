output "cluster_id" {
  description = "The unique identifier of the GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "The region in which the GKE cluster resides."
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "The IP address of the GKE control plane endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the cluster control plane."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "The Workload Identity Pool used by pods to authenticate with Google Cloud services (Pub/Sub, Cloud Storage, Cloud SQL)."
  value       = "${var.project_id}.svc.id.goog"
}

output "network_name" {
  description = "The VPC network name computed from the environment."
  value       = local.vpc_name
}

output "subnetwork_name" {
  description = "The subnetwork name computed from the environment and region."
  value       = local.subnet_name
}

output "node_service_account_email" {
  description = "The email address of the least-privilege service account attached to cluster nodes."
  value       = google_service_account.cluster_nodes.email
}

output "node_pool_names" {
  description = "List of managed node pool names created for the cluster."
  value       = [for k, pool in google_container_node_pool.pools : pool.name]
}
