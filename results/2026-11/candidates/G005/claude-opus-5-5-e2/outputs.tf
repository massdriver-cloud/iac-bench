output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Cluster resource ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Cluster location (region)."
  value       = google_container_cluster.this.location
}

output "kubectl_dns_endpoint" {
  description = "IAM-authenticated DNS endpoint of the control plane. Use: gcloud container clusters get-credentials <name> --region <region> --dns-endpoint"
  value       = try(google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint, null)
}

output "endpoint" {
  description = "IP endpoint of the control plane."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Grant workloads access to Pub/Sub, Cloud Storage, Cloud SQL, etc. directly to principal://iam.googleapis.com/projects/<project-number>/locations/global/workloadIdentityPools/<pool>/subject/ns/<namespace>/sa/<ksa>."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  description = "Email of the least-privilege node service account."
  value       = google_service_account.nodes.email
}

output "node_pools" {
  description = "Names of the node pools."
  value       = [for p in google_container_node_pool.pools : p.name]
}
