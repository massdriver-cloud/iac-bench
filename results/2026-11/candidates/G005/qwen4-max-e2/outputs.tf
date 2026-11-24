output "cluster_id" {
  description = "Fully-qualified cluster ID (projects/<project>/locations/<region>/clusters/<name>)."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the cluster."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Region the cluster lives in."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control plane endpoint (private IP by default)."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64-encoded public CA certificate of the control plane."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  description = "Email of the dedicated node service account."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind app KSAs to Google service accounts with member \"serviceAccount:<project>.svc.id.goog[<namespace>/<ksa>]\"."
  value       = "${var.project_id}.svc.id.goog"
}

output "network" {
  description = "VPC network the cluster is attached to."
  value       = local.network_name
}

output "subnetwork" {
  description = "Subnetwork the cluster is attached to."
  value       = local.subnetwork_name
}

output "upgrade_notifications_topic" {
  description = "Pub/Sub topic receiving GKE upgrade notifications for this cluster."
  value       = google_pubsub_topic.cluster_notifications.id
}

output "get_credentials_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}
