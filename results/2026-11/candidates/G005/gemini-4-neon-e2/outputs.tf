output "cluster_id" {
  description = "Full resource ID of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region where the GKE cluster control plane is hosted."
  value       = google_container_cluster.this.location
}

output "cluster_self_link" {
  description = "Self link of the GKE cluster."
  value       = google_container_cluster.this.self_link
}

output "cluster_endpoint" {
  description = "IP address of the Kubernetes API server control plane endpoint."
  value       = google_container_cluster.this.endpoint
}

output "cluster_private_endpoint" {
  description = "Internal VPC IP address of the Kubernetes API server control plane."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}

output "cluster_dns_endpoint" {
  description = "DNS endpoint for IAM-authenticated Kubernetes API access."
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public cluster root CA certificate for authenticating to the Kubernetes API."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
}

output "kubeconfig_command" {
  description = "Ready-to-run gcloud command to configure kubectl credentials for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}

output "master_version" {
  description = "Current Kubernetes control plane version."
  value       = google_container_cluster.this.master_version
}

output "release_channel" {
  description = "Configured GKE release channel."
  value       = var.release_channel
}

output "node_service_account_email" {
  description = "Email of the dedicated least-privilege GCP service account attached to cluster nodes."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool for this cluster (<project_id>.svc.id.goog)."
  value       = local.workload_pool
}

output "workload_identity_principal_prefix" {
  description = "IAM principal prefix for direct Workload Identity Federation bindings (append '/subject/ns/<namespace>/sa/<ksa_name>' when granting Pub/Sub, Cloud Storage, or Secret Manager IAM roles)."
  value       = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.workload_pool}"
}

output "network_name" {
  description = "Name of the network team's VPC used by this cluster."
  value       = data.google_compute_network.vpc.name
}

output "subnetwork_name" {
  description = "Name of the regional GKE subnet used by this cluster."
  value       = data.google_compute_subnetwork.gke.name
}

output "subnetwork_cidr" {
  description = "Primary IPv4 CIDR range of the regional GKE subnet."
  value       = data.google_compute_subnetwork.gke.ip_cidr_range
}

output "node_pools" {
  description = "Summary of managed GKE node pools created for this cluster."
  value = {
    for k, pool in google_container_node_pool.this : k => {
      id                 = pool.id
      name               = pool.name
      machine_type       = pool.node_config[0].machine_type
      min_count_per_zone = pool.autoscaling[0].min_node_count
      max_count_per_zone = pool.autoscaling[0].max_node_count
      spot               = pool.node_config[0].spot
    }
  }
}
