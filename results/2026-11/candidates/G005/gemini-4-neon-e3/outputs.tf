output "cluster_id" {
  description = "Full GCP resource ID of the GKE Standard cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE Standard cluster."
  value       = google_container_cluster.this.name
}

output "project_id" {
  description = "Google Cloud project ID hosting the cluster."
  value       = local.project_id
}

output "location" {
  description = "Google Cloud region of this regional GKE cluster."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "IP address of the Kubernetes control plane endpoint."
  value       = google_container_cluster.this.endpoint
}

output "ca_certificate" {
  description = "Base64-encoded public cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "master_version" {
  description = "Current Kubernetes version of the control plane."
  value       = google_container_cluster.this.master_version
}

output "master_ipv4_cidr_block" {
  description = "Allocated /28 IPv4 CIDR block for the private Kubernetes control plane."
  value       = local.master_ipv4_cidr_block
}

output "node_service_account_email" {
  description = "Email address of the dedicated least-privilege GKE node service account."
  value       = google_service_account.nodes.email
}

output "node_network_tag" {
  description = "Compute Engine network tag applied to all worker nodes in this cluster."
  value       = local.node_network_tag
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool for the cluster (<project_id>.svc.id.goog)."
  value       = local.workload_identity_pool
}

output "workload_identity_principal_prefix" {
  description = "IAM principal prefix for granting Pub/Sub, Cloud Storage, and Cloud SQL permissions directly to Kubernetes ServiceAccounts (append /ns/<namespace>/sa/<ksa>)."
  value       = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.workload_identity_pool}/subject"
}

output "vpc_self_link" {
  description = "Self-link of the network team's VPC used by the cluster."
  value       = data.google_compute_network.vpc.self_link
}

output "subnet_self_link" {
  description = "Self-link of the network team's regional GKE subnetwork used by the cluster."
  value       = data.google_compute_subnetwork.subnet.self_link
}

output "system_node_pool_name" {
  description = "Generated name of the dedicated GKE system node pool (null if disabled)."
  value       = var.enable_system_node_pool ? google_container_node_pool.system[0].name : null
}

output "workload_node_pool_names" {
  description = "Map of logical pool keys to generated GKE node pool names."
  value       = { for k, np in google_container_node_pool.workloads : k => np.name }
}

output "get_credentials_command" {
  description = "gcloud command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${local.project_id}${var.enable_private_endpoint ? " --internal-ip" : ""}"
}
