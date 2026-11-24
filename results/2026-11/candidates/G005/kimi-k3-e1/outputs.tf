output "cluster_name" {
  value       = google_container_cluster.this.name
  description = "Name of the cluster."
}

output "cluster_id" {
  value       = google_container_cluster.this.id
  description = "Fully qualified ID of the cluster."
}

output "cluster_location" {
  value       = google_container_cluster.this.location
  description = "Region the cluster is deployed in."
}

output "cluster_endpoint" {
  value       = google_container_cluster.this.endpoint
  description = "IP address of the control-plane endpoint (private if `enable_private_endpoint` is true)."
}

output "cluster_ca_certificate" {
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  description = "Base64-encoded CA certificate of the cluster, used to verify the control-plane endpoint."
  sensitive   = true
}

output "master_version" {
  value       = google_container_cluster.this.master_version
  description = "Current control-plane Kubernetes version."
}

output "workload_identity_pool" {
  value       = "${var.project_id}.svc.id.goog"
  description = "Workload Identity Federation pool for this project. Product teams bind their Kubernetes service accounts to IAM service accounts in this pool to reach Google Cloud APIs (Pub/Sub, Cloud Storage, Cloud SQL, ...)."
}

output "node_service_account_email" {
  value       = local.node_service_account_email
  description = "Service account used as the node identity."
}

output "network" {
  value       = var.network
  description = "VPC the cluster is deployed in."
}

output "subnetwork" {
  value       = local.subnetwork
  description = "Subnetwork the cluster nodes are deployed in."
}

output "node_pool_ids" {
  value       = { for name, pool in google_container_node_pool.pools : name => pool.id }
  description = "IDs of the managed node pools, keyed by pool name."
}

output "upgrade_notifications_topic" {
  value       = var.enable_upgrade_notifications ? google_pubsub_topic.upgrade_notifications[0].name : null
  description = "Name of the Pub/Sub topic carrying cluster upgrade and security-bulletin events (null when notifications are disabled)."
}

output "get_credentials_command" {
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id}"
  description = "Command to configure kubectl access to this cluster."
}
