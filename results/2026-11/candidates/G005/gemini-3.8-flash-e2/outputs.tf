output "cluster_id" {
  description = "The identifier of the created GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "endpoint" {
  description = "The IP address of the Kubernetes API server endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "The public certificate authority used by clients to authenticate to the Kubernetes cluster endpoint (base64 encoded)."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "location" {
  description = "The GCP region of the cluster."
  value       = google_container_cluster.primary.location
}

output "network" {
  description = "The VPC network in which the cluster is running."
  value       = google_container_cluster.primary.network
}

output "subnetwork" {
  description = "The subnetwork in which the cluster is running."
  value       = google_container_cluster.primary.subnetwork
}

output "node_service_account" {
  description = "The email address of the service account used by the node pools."
  value       = local.node_service_account_email
}

output "workload_identity_pool" {
  description = "The Workload Identity pool for authenticating workloads to GCP services."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_pools" {
  description = "Map of created node pools and their properties."
  value = {
    for k, pool in google_container_node_pool.pools : k => {
      id             = pool.id
      name           = pool.name
      node_locations = pool.node_locations
      version        = pool.version
    }
  }
}

output "get_credentials_command" {
  description = "gcloud command to configure kubectl credentials for the cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${google_container_cluster.primary.location} --project ${google_container_cluster.primary.project}"
}
