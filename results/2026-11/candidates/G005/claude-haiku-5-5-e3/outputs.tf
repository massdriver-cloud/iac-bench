output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind Kubernetes service accounts to Google service accounts with roles/iam.workloadIdentityUser on principal://iam.googleapis.com/<pool>/subject/ns/<namespace>/sa/<ksa>."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Service account the node VMs run as."
  value       = google_service_account.nodes.email
}

output "network" {
  description = "VPC network the cluster is attached to."
  value       = data.google_compute_subnetwork.gke.network
}

output "subnetwork" {
  description = "GKE subnet the cluster is attached to."
  value       = data.google_compute_subnetwork.gke.name
}

output "get_credentials_command" {
  description = "Command to fetch kubeconfig credentials for the cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}
