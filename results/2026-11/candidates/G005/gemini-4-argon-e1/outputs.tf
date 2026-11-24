output "cluster_id" {
  description = "The unique identifier of the GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "The region in which the GKE cluster is deployed."
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "The IP address of the Kubernetes API server control plane."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the cluster control plane."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "The Workload Identity pool (<project_id>.svc.id.goog) used by Kubernetes service accounts to authenticate to Google Cloud services (Pub/Sub, Cloud Storage, Cloud SQL)."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Email address of the dedicated least-privilege IAM service account attached to cluster nodes."
  value       = google_service_account.cluster_nodes.email
}

output "network_name" {
  description = "The name of the VPC network used by the cluster."
  value       = local.vpc_name
}

output "subnetwork_name" {
  description = "The name of the VPC subnetwork used by the cluster."
  value       = local.subnet_name
}

output "node_pool_names" {
  description = "List of managed node pool names created for the cluster."
  value       = [for k, pool in google_container_node_pool.pools : pool.name]
}
