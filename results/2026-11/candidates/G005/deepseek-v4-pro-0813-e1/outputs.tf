output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.cluster.name
}

output "cluster_id" {
  description = "The fully-qualified cluster id (project/location/name)."
  value       = google_container_cluster.cluster.id
}

output "cluster_location" {
  description = "The region/zone in which the cluster lives."
  value       = google_container_cluster.cluster.location
}

output "endpoint" {
  description = "The private IP address of the cluster master (control plane)."
  value       = google_container_cluster.cluster.endpoint
}

output "ca_certificate" {
  description = "Base64-encoded public certificate used by clients to authenticate to the cluster endpoint."
  value       = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "The Workload Identity pool for the cluster (empty if Workload Identity is disabled)."
  value = try(
    google_container_cluster.cluster.workload_identity_config[0].workload_pool,
    ""
  )
}

output "system_node_pool_name" {
  description = "Name of the system node pool."
  value       = google_container_node_pool.system.name
}

output "workload_node_pool_names" {
  description = "Names of the workload node pools."
  value       = { for k, v in google_container_node_pool.workload : k => v.name }
}