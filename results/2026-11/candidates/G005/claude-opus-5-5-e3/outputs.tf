output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Cluster resource ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Cluster region."
  value       = google_container_cluster.this.location
}

output "dns_endpoint" {
  description = "IAM-authenticated DNS control-plane endpoint (use: gcloud container clusters get-credentials <name> --region <region> --dns-endpoint)."
  value       = try(google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint, null)
}

output "private_endpoint" {
  description = "Private IP of the control plane."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}

output "ca_certificate" {
  description = "Cluster CA certificate (base64)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Grant GCP roles (Pub/Sub, Storage, Cloud SQL...) to principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<pool>/subject/ns/<ns>/sa/<ksa> or via a GSA bound with roles/iam.workloadIdentityUser."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  description = "Email of the node service account (not for workload use)."
  value       = google_service_account.nodes.email
}

output "release_channel" {
  description = "Effective release channel."
  value       = local.release_channel
}
