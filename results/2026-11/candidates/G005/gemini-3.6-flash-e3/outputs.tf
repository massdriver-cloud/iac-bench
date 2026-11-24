output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_id" {
  description = "An identifier for the resource with format projects/{{project}}/locations/{{location}}/clusters/{{name}}"
  value       = google_container_cluster.primary.id
}

output "cluster_endpoint" {
  description = "The IP address of the cluster master endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 encoded public certificate used by clients to authenticate to the cluster endpoint."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "The location (region) of the GKE cluster."
  value       = google_container_cluster.primary.location
}

output "service_account_email" {
  description = "The email address of the service account created for GKE nodes."
  value       = google_service_account.gke_nodes.email
}

output "service_account_id" {
  description = "The GKEY node service account ID."
  value       = google_service_account.gke_nodes.id
}

output "workload_identity_pool" {
  description = "The Workload Identity pool for the cluster."
  value       = "${var.project_id}.svc.id.goog"
}

output "network" {
  description = "The VPC network name used for the cluster."
  value       = local.network_name
}

output "subnetwork" {
  description = "The subnetwork name used for the cluster."
  value       = local.subnet_name
}
