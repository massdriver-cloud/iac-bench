output "cluster_id" {
  description = "Fully qualified Terraform/Google Cloud ID of the cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the cluster."
  value       = google_container_cluster.this.name
}

output "project_id" {
  description = "Project containing the cluster."
  value       = var.project_id
}

output "location" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "Control plane endpoint. With the default private endpoint, this is reachable only through authorized private connectivity."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate for a separately configured Kubernetes provider."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "get_credentials_command" {
  description = "Command for an engineer with suitable IAM and network access to configure kubectl."
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "network_self_link" {
  description = "Existing environment VPC used by the cluster."
  value       = local.network_self_link
}

output "subnetwork_self_link" {
  description = "Existing regional GKE subnet used by the cluster. Its pods and services secondary ranges are used for native VPC networking."
  value       = local.subnetwork_self_link
}

output "node_service_account_email" {
  description = "Dedicated least-privilege identity used only by cluster nodes."
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool used when binding Kubernetes and Google service accounts."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_pool_names" {
  description = "Names of the managed system and application node pools."
  value       = [for pool in google_container_node_pool.this : pool.name]
}

output "workload_identity_bindings" {
  description = "Kubernetes identities and the annotation required on each Kubernetes service account."
  value = {
    for key, binding in var.workload_identity_bindings : key => {
      kubernetes_service_account = "${binding.namespace}/${binding.kubernetes_service_account}"
      google_service_account     = binding.google_service_account_email
      required_annotation        = "iam.gke.io/gcp-service-account=${binding.google_service_account_email}"
    }
  }
}
