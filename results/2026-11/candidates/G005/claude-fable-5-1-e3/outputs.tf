output "cluster_id" {
  description = "Fully qualified cluster id (projects/.../locations/.../clusters/...)."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Region the cluster runs in."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Kubernetes API endpoint IP."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the cluster."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "network" {
  description = "VPC and subnet the cluster was attached to."
  value = {
    network    = local.network
    subnetwork = local.subnetwork
  }
}

output "node_service_account_email" {
  description = "Service account used by the nodes."
  value       = google_service_account.nodes.email
}

output "node_pools" {
  description = "Names of the node pools created."
  value       = keys(google_container_node_pool.this)
}

output "workload_identity_pool" {
  description = "Workload Identity pool to reference in KSA annotations."
  value       = "${var.project_id}.svc.id.goog"
}

output "workload_service_accounts" {
  description = "Google service account emails per workload, and the annotation to put on the Kubernetes service account."
  value = {
    for id, sa in google_service_account.workload : id => {
      email                      = sa.email
      namespace                  = var.workload_service_accounts[id].namespace
      kubernetes_service_account = var.workload_service_accounts[id].kubernetes_service_account
      annotation                 = "iam.gke.io/gcp-service-account=${sa.email}"
    }
  }
}

output "get_credentials_command" {
  description = "gcloud command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}
