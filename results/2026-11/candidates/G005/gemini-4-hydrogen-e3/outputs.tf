output "cluster_id" {
  description = "Full resource ID of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region where the GKE cluster is deployed."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Kubernetes control plane endpoint IP address."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the GKE cluster."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool for Kubernetes ServiceAccount to Google ServiceAccount IAM bindings."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Email of the least-privilege IAM service account attached to worker nodes."
  value       = google_service_account.nodes.email
}

output "vpc_name" {
  description = "Resolved VPC network name used by the cluster."
  value       = local.vpc_name
}

output "subnetwork_name" {
  description = "Resolved subnetwork name used by the cluster."
  value       = local.subnetwork_name
}

output "node_pool_names" {
  description = "Names of the managed GKE Standard node pools."
  value       = [for p in google_container_node_pool.pools : p.name]
}

output "get_credentials_command" {
  description = "gcloud command to configure local kubectl access for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}
