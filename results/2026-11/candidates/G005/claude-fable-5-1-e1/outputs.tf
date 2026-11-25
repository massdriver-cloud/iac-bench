output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified cluster id (projects/.../locations/.../clusters/...)."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Region the cluster runs in."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "IP address of the Kubernetes API server."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64-encoded public certificate of the cluster CA."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "master_version" {
  description = "Kubernetes version currently running on the control plane."
  value       = google_container_cluster.this.master_version
}

output "node_service_account_email" {
  description = "Email of the service account node VMs run as."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool; bind Kubernetes service accounts to Google service accounts with members of the form serviceAccount:<pool>[<namespace>/<ksa>]."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_pools" {
  description = "Names of the node pools created in the cluster."
  value       = { for k, np in google_container_node_pool.this : k => np.name }
}

output "network" {
  description = "VPC the cluster is attached to."
  value       = local.vpc_name
}

output "subnetwork" {
  description = "Subnet the cluster's nodes live in."
  value       = local.subnet_name
}

output "get_credentials_command" {
  description = "gcloud command that configures kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}
