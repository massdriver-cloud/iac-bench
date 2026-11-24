output "cluster_name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "private_endpoint" {
  description = "Private API address; requires network connectivity and IAM/RBAC authorization."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
  sensitive   = true
}

output "get_credentials_command" {
  description = "Run from an authorized host with private control-plane connectivity and gke-gcloud-auth-plugin installed."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id} --internal-ip"
}

output "node_service_account_email" {
  value = google_service_account.nodes.email
}

output "workload_pool" {
  value = "${var.project_id}.svc.id.goog"
}

output "workload_service_accounts" {
  description = "Grant resource-specific IAM roles to these emails; annotate each matching KSA with iam.gke.io/gcp-service-account=<email>."
  value       = { for key, sa in google_service_account.workload : key => sa.email }
}

output "node_pool_names" {
  value = { for key, pool in google_container_node_pool.this : key => pool.name }
}
