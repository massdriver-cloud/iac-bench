output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully-qualified cluster ID (project/location/name)."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Region the cluster runs in."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control plane address used by kubectl."
  value       = google_container_cluster.this.endpoint
}

output "private_endpoint" {
  description = "Private IP of the control plane inside the VPC."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}

output "public_endpoint" {
  description = "Public IP of the control plane (unreachable until master_authorized_networks is populated; empty when the endpoint is private-only)."
  value       = google_container_cluster.this.private_cluster_config[0].public_endpoint
}

output "master_version" {
  description = "Kubernetes version of the control plane."
  value       = google_container_cluster.this.master_version
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64-encoded)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind Google service accounts to Kubernetes service accounts with the IAM role roles/iam.workloadIdentityUser on member \"serviceAccount:<project>.svc.id.goog[<namespace>/<ksa>]\"."
  value       = local.workload_pool
}

output "node_service_account_email" {
  description = "Email of the node service account created for this cluster."
  value       = google_service_account.nodes.email
}

output "subnetwork_name" {
  description = "Subnet the cluster was deployed into."
  value       = local.subnetwork_name
}
