output "cluster_id" {
  description = "The unique identifier of the GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "The region where the GKE cluster is deployed."
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "The IP address of the GKE control plane endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The base64-encoded public CA certificate of the GKE cluster."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "The Workload Identity pool used by the cluster (<project_id>.svc.id.goog) for binding Kubernetes ServiceAccounts to Google ServiceAccounts."
  value       = "${var.project_id}.svc.id.goog"
}

output "network" {
  description = "The VPC network self-link used by the cluster."
  value       = local.network_self_link
}

output "subnetwork" {
  description = "The subnetwork self-link used by the cluster."
  value       = local.subnetwork_self_link
}

output "node_service_account_email" {
  description = "The email address of the dedicated least-privilege Google Service Account attached to cluster nodes."
  value       = google_service_account.node_sa.email
}

output "node_pool_names" {
  description = "List of managed node pool names in the cluster."
  value       = keys(google_container_node_pool.pools)
}
