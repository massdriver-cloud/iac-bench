output "cluster_id" {
  description = "Fully qualified regional cluster ID."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control-plane endpoint; private unless public access is explicitly enabled."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA; no credentials or client certificates are generated."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "network" {
  value = local.network
}

output "subnetwork" {
  value = local.subnetwork
}

output "node_service_account_email" {
  value = google_service_account.nodes.email
}

output "workload_pool" {
  value = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_pool_names" {
  value = { for name, pool in google_container_node_pool.this : name => pool.name }
}

output "workload_service_account_emails" {
  description = "Use these identities for resource-scoped IAM (for example on individual buckets or Pub/Sub topics)."
  value       = { for name, account in google_service_account.workload : name => account.email }
}

output "workload_service_account_annotations" {
  description = "Apply each annotation to the corresponding existing Kubernetes service account."
  value = { for name, identity in var.workload_identities : name => {
    namespace       = identity.namespace
    service_account = identity.kubernetes_service_account
    annotations     = { "iam.gke.io/gcp-service-account" = google_service_account.workload[name].email }
  } }
}

output "get_credentials_command" {
  description = "Requires gcloud, gke-gcloud-auth-plugin, cluster IAM/RBAC, and connectivity from an authorized management network."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --project ${var.project_id} --region ${var.region}${var.enable_public_endpoint ? "" : " --internal-ip"}"
}
