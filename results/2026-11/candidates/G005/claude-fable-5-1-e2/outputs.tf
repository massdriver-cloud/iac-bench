output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified cluster ID (projects/.../locations/.../clusters/...)."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Region the cluster runs in."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "IP address of the Kubernetes API server."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the cluster."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "master_version" {
  description = "Current Kubernetes version of the control plane."
  value       = google_container_cluster.this.master_version
}

output "network" {
  description = "VPC the cluster is attached to."
  value       = local.vpc_name
}

output "subnetwork" {
  description = "Subnet the cluster nodes live in."
  value       = local.subnet_name
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Bind Kubernetes service accounts to Google service accounts with `roles/iam.workloadIdentityUser` for member `serviceAccount:<pool>[<namespace>/<ksa>]`."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Email of the dedicated node service account."
  value       = google_service_account.nodes.email
}

output "node_pools" {
  description = "Created node pools: actual GKE name and configured machine type per logical pool."
  value = {
    for k, p in google_container_node_pool.this : k => {
      name         = p.name
      machine_type = p.node_config[0].machine_type
      min_nodes    = p.autoscaling[0].min_node_count
      max_nodes    = p.autoscaling[0].max_node_count
    }
  }
}

output "get_credentials_command" {
  description = "gcloud command that configures kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}
