output "cluster_id" {
  description = "Fully-qualified cluster ID (projects/<project>/locations/<region>/clusters/<name>)."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region the cluster lives in."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Control-plane endpoint IP."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the control plane."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool; annotate KSAs with <project>.svc.id.goog[<namespace>/<ksa>]."
  value       = local.workload_identity_pool
}

output "node_service_account" {
  description = "Email of the least-privilege node service account."
  value       = google_service_account.nodes.email
}

output "workload_identity_emails" {
  description = "Map of workload identity key => Google service account email. Annotate the matching KSA with iam.gke.io/gcp-service-account=<email>."
  value       = { for k, sa in google_service_account.workload : k => sa.email }
}

output "get_credentials_command" {
  description = "Command engineers use to configure kubectl."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}

output "network" {
  description = "VPC and subnet the cluster was placed in."
  value = {
    vpc    = local.vpc_name
    subnet = local.subnet_name
  }
}
