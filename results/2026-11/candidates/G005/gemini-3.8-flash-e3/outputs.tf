output "cluster_id" {
  description = "The unique identifier of the GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "location" {
  description = "The location (region) of the GKE cluster."
  value       = google_container_cluster.primary.location
}

output "endpoint" {
  description = "The IP address of the Kubernetes control plane endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "The public root CA certificate used to communicate with the cluster (base64-encoded)."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "network" {
  description = "The VPC network where the GKE cluster is provisioned."
  value       = google_container_cluster.primary.network
}

output "subnetwork" {
  description = "The subnetwork where the GKE cluster is provisioned."
  value       = google_container_cluster.primary.subnetwork
}

output "master_ipv4_cidr_block" {
  description = "The /28 IP CIDR block allocated for the GKE control plane."
  value       = google_container_cluster.primary.private_cluster_config[0].master_ipv4_cidr_block
}

output "workload_identity_pool" {
  description = "The Workload Identity pool for authenticating workloads to GCP services."
  value       = google_container_cluster.primary.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  description = "The email address of the service account used by the GKE node pools."
  value       = local.node_service_account_email
}

output "node_pools" {
  description = "Map of created node pools with their respective configuration and IDs."
  value = {
    for k, v in google_container_node_pool.pools : k => {
      id             = v.id
      name           = v.name
      version        = v.version
      min_node_count = v.autoscaling[0].min_node_count
      max_node_count = v.autoscaling[0].max_node_count
    }
  }
}
