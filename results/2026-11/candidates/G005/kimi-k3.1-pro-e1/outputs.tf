output "cluster_name" {
  description = "Name of the created GKE Standard cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified provider ID of the cluster."
  value       = google_container_cluster.this.id
}

output "cluster_location" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Control-plane endpoint. With the default private endpoint, this is reachable only from connected private networks."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate for Kubernetes clients."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "network" {
  description = "ID of the existing environment VPC used by the cluster. The network remains network-team owned."
  value       = local.network_id
}

output "subnetwork" {
  description = "ID of the existing GKE subnet with pods and services secondary ranges. The subnet remains network-team owned."
  value       = local.subnetwork_id
}

output "node_service_account_email" {
  description = "Email of the least-privilege node service account. Grant external image repositories access to this identity only when required."
  value       = google_service_account.nodes.email
}

output "node_pool_names" {
  description = "Names of the separately managed node pools."
  value       = sort(keys(google_container_node_pool.this))
}

output "workload_service_accounts" {
  description = "Application Google service accounts and the annotation to place on each associated Kubernetes service account."
  value = {
    for account_id, account in google_service_account.workloads : account_id => {
      email = account.email
      kubernetes_service_account_annotation = {
        "iam.gke.io/gcp-service-account" = account.email
      }
      kubernetes_identities = var.workload_service_accounts[account_id].kubernetes_service_accounts
    }
  }
}

output "workload_identity_pool" {
  description = "Workload Identity pool used to bind Kubernetes and Google service accounts."
  value       = "${var.project_id}.svc.id.goog"
}

output "secrets_kms_key_id" {
  description = "CMEK used for application-layer encryption of Kubernetes Secrets."
  value       = google_kms_crypto_key.gke_secrets.id
}

output "cluster_notifications_topic" {
  description = "Pub/Sub topic receiving GKE upgrade and security-bulletin notifications. Attach operational subscriptions outside this module."
  value       = google_pubsub_topic.cluster_notifications.id
}
