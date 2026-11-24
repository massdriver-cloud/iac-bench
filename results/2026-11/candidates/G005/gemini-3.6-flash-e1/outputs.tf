output "cluster_id" {
  description = "The ID of the created GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the created GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The IP address of the cluster control plane."
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "The public certificate of the cluster's CA (base64 encoded)."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "location" {
  description = "The region or zone where the cluster is located."
  value       = google_container_cluster.primary.location
}

output "network" {
  description = "The VPC network the cluster is connected to."
  value       = google_container_cluster.primary.network
}

output "subnetwork" {
  description = "The subnetwork the cluster is connected to."
  value       = google_container_cluster.primary.subnetwork
}

output "service_account_email" {
  description = "The email address of the service account used by the cluster nodes."
  value       = local.node_sa_email
}

output "workload_identity_pool" {
  description = "The Workload Identity pool for the cluster."
  value       = "${var.project_id}.svc.id.goog"
}

output "master_version" {
  description = "The current Kubernetes master version of the cluster."
  value       = google_container_cluster.primary.master_version
}
