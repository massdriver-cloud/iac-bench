output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified GKE cluster ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Regional cluster location."
  value       = google_container_cluster.this.location
}

output "private_endpoint" {
  description = "Private Kubernetes API endpoint; accessible only through routed private connectivity."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}

output "workload_identity_pool" {
  description = "Use per-workload Kubernetes identities for Google Cloud IAM, never node credentials."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  description = "Node identity; do not grant application data permissions to this identity."
  value       = google_service_account.nodes.email
}

output "get_credentials_command" {
  description = "Run from a host connected to the VPC, with gcloud and gke-gcloud-auth-plugin installed."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id} --internal-ip"
}
