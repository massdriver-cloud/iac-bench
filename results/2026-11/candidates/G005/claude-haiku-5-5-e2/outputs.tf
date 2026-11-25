output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Control plane endpoint IP. Reachable only as allowed by the endpoint settings."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind Google service accounts to Kubernetes service accounts with this pool."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Email of the dedicated node service account."
  value       = google_service_account.nodes.email
}

output "node_pool_names" {
  description = "Names of the node pools."
  value       = [for p in google_container_node_pool.this : p.name]
}

output "vpc_name" {
  description = "Network team VPC the cluster is attached to."
  value       = data.google_compute_network.apps.name
}

output "subnetwork_name" {
  description = "GKE subnet the cluster is attached to."
  value       = data.google_compute_subnetwork.gke.name
}
