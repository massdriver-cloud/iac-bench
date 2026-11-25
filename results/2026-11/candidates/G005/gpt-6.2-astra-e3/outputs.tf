output "cluster_id" {
  description = "Regional GKE cluster resource identifier."
  value       = google_container_cluster.this.id
}

output "workload_pool" {
  description = "Trust domain for workload identities (shared within the project)."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  description = "Node VM identity, for repository-scoped image pull grants."
  value       = google_service_account.nodes.email
}

output "credentials_command" {
  description = "Run from a host that can route to the private control plane."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --project ${var.project_id} --region ${var.region} --internal-ip"
}
