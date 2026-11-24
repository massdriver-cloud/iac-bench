output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Unique identifier of the cluster."
  value       = google_container_cluster.this.id
}

output "cluster_location" {
  description = "Region the regional cluster runs in."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "IP address of the cluster's Kubernetes API server (private endpoint)."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate used to verify the cluster's API server."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_master_version" {
  description = "Kubernetes version currently running on the control plane."
  value       = google_container_cluster.this.master_version
}

output "node_pool_name" {
  description = "Name of the primary node pool product teams schedule onto."
  value       = google_container_node_pool.primary.name
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind Kubernetes service accounts to Google IAM service accounts in this pool so pods can call Pub/Sub, Cloud Storage and Cloud SQL."
  value       = local.workload_pool
}

output "node_service_account_email" {
  description = "Email of the dedicated node service account."
  value       = google_service_account.nodes.email
}

output "network" {
  description = "VPC the cluster is attached to."
  value       = local.network_name
}

output "subnetwork" {
  description = "Subnet hosting the cluster's nodes."
  value       = local.subnetwork_name
}

output "get_credentials_command" {
  description = "gcloud command to fetch kubeconfig for the cluster (requires private-network reachability, e.g. via VPN)."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${local.project_id}"
}
