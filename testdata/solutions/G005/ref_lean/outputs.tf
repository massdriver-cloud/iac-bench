output "cluster_name" {
  description = "Cluster name, for gcloud container clusters get-credentials --dns-endpoint."
  value       = google_container_cluster.this.name
}

output "node_service_account" {
  description = "Service account the nodes run as."
  value       = google_service_account.nodes.email
}
