output "cluster_name" {
  description = "Name of the created GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified GKE cluster ID."
  value       = google_container_cluster.this.id
}

output "region" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "control_plane_endpoint" {
  description = "Control-plane endpoint. With the defaults this is a private IP reachable only from an authorized private network path."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate for Kubernetes client configuration."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool used to annotate Kubernetes service accounts."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Email of the minimally privileged node service account. It is not intended for application workloads."
  value       = google_service_account.nodes.email
}

output "workload_service_account_emails" {
  description = "Map of workload service account IDs to Google service account emails for Kubernetes service-account annotations."
  value = {
    for account_id, account in google_service_account.workload : account_id => account.email
  }
}

output "network_name" {
  description = "Environment VPC selected by the module."
  value       = local.network_name
}

output "subnetwork_name" {
  description = "Pre-existing GKE subnetwork selected by the module."
  value       = local.subnetwork_name
}

output "master_ipv4_cidr_block" {
  description = "Private control-plane /28 allocated to this cluster."
  value       = var.master_ipv4_cidr_block
}
