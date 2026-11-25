output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified id of the cluster, e.g. projects/<project>/locations/<region>/clusters/<name>."
  value       = google_container_cluster.this.id
}

output "cluster_endpoint" {
  description = "Address of the Kubernetes API server. Reachable only from the master_authorized_networks, or from the VPC when enable_private_endpoint is true."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Public CA certificate of the cluster, base64-encoded; use it as certificate-authority-data in kubeconfig."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "master_version" {
  description = "Kubernetes version the control plane runs; owned by the release channel."
  value       = google_container_cluster.this.master_version
}

output "region" {
  description = "Region the cluster runs in."
  value       = var.region
}

output "network" {
  description = "VPC the cluster is attached to (owned by the network team)."
  value       = local.network
}

output "subnetwork" {
  description = "Subnet the cluster nodes use (owned by the network team)."
  value       = local.subnetwork
}

output "workload_identity_pool" {
  description = "Workload Identity pool of the cluster: <project>.svc.id.goog. Kubernetes service accounts in this pool impersonate the Google service accounts bound via workload_identity_bindings."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Email of the cluster's node identity. Useful when teams need to add an exception (see additional_node_service_account_roles) or audit IAM."
  value       = google_service_account.nodes.email
}

output "node_pool_names" {
  description = "Names of the managed node pools attached to the cluster."
  value       = keys(var.node_pools)
}
