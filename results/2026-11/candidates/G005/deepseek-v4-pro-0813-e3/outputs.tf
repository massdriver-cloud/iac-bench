output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region of the GKE cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Control-plane endpoint reported by GKE."
  value       = google_container_cluster.this.endpoint
}

output "cluster_id" {
  description = "Fully qualified GKE cluster identifier."
  value       = google_container_cluster.this.id
}

output "node_pool_ids" {
  description = "Map of node pool names to their fully qualified GKE identifiers."
  value       = { for name, pool in google_container_node_pool.this : name => pool.id }
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this project. Bind Kubernetes service accounts to Google service accounts in this pool."
  value       = "${var.project_id}.svc.id.goog"
}