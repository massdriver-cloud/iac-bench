output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified cluster ID (projects/.../locations/.../clusters/...)."
  value       = google_container_cluster.this.id
}

output "region" {
  description = "Region the cluster runs in. The cluster is regional: multi-zone control plane, nodes spread across zones."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control-plane endpoint IP address."
  value       = google_container_cluster.this.endpoint
}

output "ca_certificate" {
  description = "Base64-encoded cluster CA certificate, for kubeconfigs."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "master_version" {
  description = "Current control-plane version (managed automatically by the release channel)."
  value       = google_container_cluster.this.master_version
}

output "network" {
  description = "VPC the cluster runs in."
  value       = var.network
}

output "subnetwork" {
  description = "Subnetwork the cluster nodes run in."
  value       = local.subnetwork
}

output "node_service_account_email" {
  description = "Email of the dedicated, least-privilege node service account."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this project. Kubernetes service accounts are bound as serviceAccount:<pool>[<namespace>/<ksa-name>]."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_pools" {
  description = "Node pools managed by this module, keyed by pool name."
  value       = { for name, pool in google_container_node_pool.this : name => pool.id }
}

output "workload_service_account_emails" {
  description = "Emails of the Google service accounts created for product-team workloads, keyed by account id. Teams reference these in the iam.gke.io/gcp-service-account annotation of their Kubernetes service accounts."
  value       = { for id, sa in google_service_account.workload : id => sa.email }
}

output "get_credentials_command" {
  description = "Command that configures kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${var.name} --region ${var.region} --project ${var.project_id}"
}
