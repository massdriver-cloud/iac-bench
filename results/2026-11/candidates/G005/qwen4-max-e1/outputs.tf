output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully-qualified cluster ID (projects/<project>/locations/<region>/clusters/<name>)."
  value       = google_container_cluster.this.id
}

output "cluster_location" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint (private IP when enable_private_endpoint is true)."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the API server."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind product-team Kubernetes service accounts to Google service accounts with member 'principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<this value>/subject/system:serviceaccount:<namespace>:<ksa>'."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Email of the dedicated, least-privilege node service account. Do NOT grant application permissions to it; use Workload Identity for workloads."
  value       = google_service_account.nodes.email
}

output "network" {
  description = "VPC the cluster is attached to."
  value       = local.network_name
}

output "subnetwork" {
  description = "Subnet the cluster is attached to."
  value       = local.subnetwork_name
}

output "get_credentials_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}
