output "cluster_id" {
  description = "The unique identifier of the GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The IP address of the GKE cluster control plane."
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "The base64 encoded public certificate that is the CA of the cluster."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "location" {
  description = "The location (region) of the cluster."
  value       = google_container_cluster.primary.location
}

output "region" {
  description = "The region of the cluster."
  value       = var.region
}

output "network" {
  description = "The network where the GKE cluster is deployed."
  value       = var.network
}

output "subnetwork" {
  description = "The subnetwork where the GKE cluster is deployed."
  value       = local.subnet_name
}

output "service_account_email" {
  description = "The email address of the custom service account created for GKE node pools."
  value       = local.node_service_account_email
}

output "workload_identity_pool" {
  description = "The Workload Identity pool for binding GCP IAM roles to K8s ServiceAccounts."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_pools" {
  description = "Map of created node pools and their IDs."
  value       = { for k, v in google_container_node_pool.pools : k => v.id }
}
