# ===========================================================================
# Outputs
# ===========================================================================

output "cluster_name" {
  description = "Name of the cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully-qualified id of the cluster."
  value       = google_container_cluster.this.id
}

output "cluster_location" {
  description = "Region the cluster runs in."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Control plane endpoint. With a private endpoint this is only reachable from the VPC."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Public CA certificate of the cluster, base64-encoded. Combine with cluster_endpoint to build a kubeconfig."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account" {
  description = "Email of the cluster's dedicated node service account."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool of the cluster, e.g. my-project.svc.id.goog."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_pools" {
  description = "Node pools managed by this module, with their autoscaling bounds."
  value = {
    for name, pool in local.node_pools : name => {
      machine_type = pool.machine_type
      min_count    = pool.min_count
      max_count    = pool.max_count
      spot         = pool.spot
    }
  }
}
