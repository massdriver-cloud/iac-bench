output "cluster_id" {
  description = "The fully qualified identifier of the GKE cluster"
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "location" {
  description = "The GCP region of the GKE cluster"
  value       = google_container_cluster.primary.location
}

output "endpoint" {
  description = "The IP address of the Kubernetes control plane API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "The public root CA certificate used by the cluster (base64-encoded)"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "network" {
  description = "The VPC network where the GKE cluster is provisioned"
  value       = google_container_cluster.primary.network
}

output "subnetwork" {
  description = "The subnetwork where the GKE cluster and node pools are provisioned"
  value       = google_container_cluster.primary.subnetwork
}

output "workload_identity_pool" {
  description = "The Workload Identity pool for binding Kubernetes service accounts to Google IAM service accounts"
  value       = google_container_cluster.primary.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "The email address of the IAM service account used by the worker nodes"
  value       = local.node_service_account_email
}

output "node_pools" {
  description = "Map of created node pools and their properties"
  value = {
    for k, v in google_container_node_pool.pools : k => {
      name        = v.name
      version     = v.version
      autoscaling = v.autoscaling
    }
  }
}
