output "cluster_name" {
  description = "Name of the cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Full resource ID of the cluster (projects/<p>/locations/<region>/clusters/<name>)."
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

output "release_channel" {
  description = "Release channel the cluster follows."
  value       = local.release_channel
}

output "network" {
  description = "VPC the cluster is attached to."
  value       = local.vpc_name
}

output "subnetwork" {
  description = "Subnet the cluster's nodes live in."
  value       = local.subnet_name
}

output "dns_endpoint" {
  description = "IAM-authenticated DNS endpoint of the Kubernetes API. This is how people and CI reach the cluster."
  value       = try(google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint, null)
}

output "private_endpoint" {
  description = "Private IP endpoint of the Kubernetes API, reachable only from inside the VPC."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate (only needed with the private IP endpoint)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "get_credentials_command" {
  description = "Command that configures kubectl for this cluster through the DNS endpoint."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --location ${google_container_cluster.this.location} --project ${local.project_id} --dns-endpoint"
}

output "node_pools" {
  description = "Names of the node pools managed by this module."
  value       = sort([for p in google_container_node_pool.this : p.name])
}

output "node_service_account_email" {
  description = "Service account the nodes run as. Grant it artifactregistry.reader on image repositories in other projects; do NOT grant it access workloads need."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool of the cluster."
  value       = local.workload_pool
}

output "workload_identity_principal_format" {
  description = "IAM principal for a Kubernetes service account. Replace NAMESPACE and KSA_NAME, then grant that principal the Pub/Sub, Cloud Storage, Cloud SQL, ... roles the workload needs."
  value       = "principal://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${local.workload_pool}/subject/ns/NAMESPACE/sa/KSA_NAME"
}

output "secrets_encryption_kms_key" {
  description = "Cloud KMS key that encrypts Kubernetes Secrets in this cluster."
  value       = local.secrets_kms_key_name
}
