output "cluster_name" {
  description = "Name of the cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Full resource ID of the cluster (projects/<project>/locations/<region>/clusters/<name>)."
  value       = google_container_cluster.this.id
}

output "project_id" {
  description = "Project the cluster lives in."
  value       = local.project_id
}

output "region" {
  description = "Region of the cluster."
  value       = google_container_cluster.this.location
}

output "network" {
  description = "VPC the cluster is attached to."
  value       = local.vpc_name
}

output "subnetwork" {
  description = "Subnet the cluster's nodes live in."
  value       = local.subnet_name
}

output "release_channel" {
  description = "Release channel the cluster follows."
  value       = local.release_channel
}

output "get_credentials_command" {
  description = "Run this to get kubectl access through the IAM-authenticated DNS endpoint (works from anywhere; needs roles/container.developer or similar on the cluster)."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --location ${google_container_cluster.this.location} --project ${local.project_id} --dns-endpoint"
}

output "dns_endpoint" {
  description = "IAM-authenticated DNS endpoint of the control plane."
  value       = try(google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint, null)
}

output "private_endpoint" {
  description = "Private IP endpoint of the control plane (reachable only from the VPC ranges in control_plane_authorized_networks)."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the cluster, for clients that use the private IP endpoint."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Grant a workload access to Pub/Sub, Cloud Storage, Cloud SQL etc. by giving an IAM role to principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<this value>/subject/ns/<NAMESPACE>/sa/<KUBERNETES_SERVICE_ACCOUNT>."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Service account the nodes run as. Do not grant it application permissions."
  value       = google_service_account.nodes.email
}

output "node_pool_names" {
  description = "Names of the node pools."
  value       = sort([for p in google_container_node_pool.this : p.name])
}
