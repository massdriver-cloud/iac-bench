output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified GKE cluster ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Regional control-plane location."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Kubernetes API endpoint; routing and authorized-network access are still required."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate (not a client credential)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Project-wide Workload Identity pool."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account" {
  description = "Dedicated node service account email; never use this identity for application permissions."
  value       = google_service_account.nodes.email
}

output "workload_service_accounts" {
  description = "Kubernetes service accounts to create, with required GSA annotations. Assign their names to Pod spec.serviceAccountName."
  value = {
    for account, workload in var.workload_identities : account => {
      email           = google_service_account.workload[account].email
      namespace       = workload.namespace
      service_account = workload.service_account
      annotations     = { "iam.gke.io/gcp-service-account" = google_service_account.workload[account].email }
    }
  }
}

output "node_pool_names" {
  description = "Managed node pool names."
  value       = { for name, pool in google_container_node_pool.this : name => pool.name }
}

output "get_credentials_command" {
  description = "Run from an authorized, connected administrative workstation with gke-gcloud-auth-plugin installed."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id}${var.private_endpoint ? " --internal-ip" : ""}"
}
