output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified cluster ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Region the cluster runs in."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control plane endpoint. With enable_private_endpoint = true (platform default) it is reachable only from inside the VPC."
  value       = google_container_cluster.this.endpoint
}

output "master_version" {
  description = "Control plane version in use."
  value       = google_container_cluster.this.master_version
}

output "ca_certificate" {
  description = "Cluster CA certificate (base64)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "master_ipv4_cidr_block" {
  description = "RFC1918 /28 used by the private control plane."
  value       = google_container_cluster.this.private_cluster_config[0].master_ipv4_cidr_block
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this cluster. Bind workload Google service accounts with: roles/iam.workloadIdentityUser on member serviceAccount:<pool>[<namespace>/<kubernetes-service-account>]."
  value       = local.workload_pool
}

output "node_service_account_email" {
  description = "Email of the module-managed node service account."
  value       = google_service_account.nodes.email
}

output "subnetwork_name" {
  description = "GKE subnet the cluster is attached to."
  value       = local.subnetwork_name
}
