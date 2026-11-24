output "cluster_id" {
  description = "Fully-qualified cluster identifier."
  value       = google_container_cluster.cluster.id
}

output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "endpoint" {
  description = "Control-plane endpoint."
  value       = google_container_cluster.cluster.endpoint
}

output "ca_certificate" {
  description = "Base64 cluster CA certificate for kubeconfig generation."
  value       = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  description = "Email of the dedicated node service account."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this cluster's project (product teams bind KSAs to GSAs using it)."
  value       = "${var.project_id}.svc.id.goog"
}

output "subnetwork" {
  description = "Self link of the GKE subnet the cluster uses."
  value       = data.google_compute_subnetwork.gke_subnet.self_link
}