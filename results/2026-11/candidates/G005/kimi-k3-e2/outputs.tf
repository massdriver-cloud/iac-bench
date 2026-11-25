output "cluster_name" {
  description = "Name of the cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified cluster ID (projects/<p>/locations/<l>/clusters/<n>)."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Region of the cluster."
  value       = google_container_cluster.this.location
}

output "master_version" {
  description = "Current control plane version."
  value       = google_container_cluster.this.master_version
}

output "endpoint" {
  description = "Control plane endpoint (use with ca_certificate to configure kubectl)."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64-encoded public CA certificate of the control plane."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this project. Product teams map Kubernetes service accounts to Google service accounts with roles/iam.workloadIdentityUser on \"<pool>/<k8s-namespace>/<ksa>\"."
  value       = "${local.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Email of the least-privilege service account used by cluster nodes."
  value       = google_service_account.nodes.email
}

output "network" {
  description = "VPC the cluster runs in."
  value       = data.google_compute_network.vpc.name
}

output "subnetwork" {
  description = "Subnetwork the cluster runs in."
  value       = data.google_compute_subnetwork.gke.name
}

output "node_pool_names" {
  description = "Names of the node pools managed for this cluster."
  value       = sort(keys(google_container_node_pool.this))
}
