output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Regional control plane location."
  value       = google_container_cluster.this.location
}

output "private_endpoint" {
  description = "Private Kubernetes API IP; only accessible over approved network paths."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded Kubernetes cluster CA."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "get_credentials_command" {
  description = "Run from an authorized private network with gcloud and gke-gcloud-auth-plugin installed."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --project ${var.project_id} --region ${var.region} --internal-ip"
}

output "node_service_account" {
  description = "Dedicated node identity; never use this identity for product workloads."
  value       = google_service_account.nodes.email
}

output "workload_pool" {
  description = "Workload Identity pool. Namespace/KSA names are identity boundaries shared by clusters in this project."
  value       = "${var.project_id}.svc.id.goog"
}

output "workload_identities" {
  description = "Annotate each KSA with iam.gke.io/gcp-service-account = gcp_service_account_email."
  value = {
    for key, identity in var.workload_identities : key => {
      namespace                  = identity.namespace
      kubernetes_service_account = identity.kubernetes_service_account
      gcp_service_account_email  = google_service_account.workload[key].email
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.workload[key].email
      }
    }
  }
}

output "node_pool_names" {
  description = "Managed on-demand node pools."
  value       = { for key, pool in google_container_node_pool.this : key => pool.name }
}
