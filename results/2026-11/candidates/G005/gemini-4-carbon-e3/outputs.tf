output "cluster_id" {
  description = "Fully qualified resource ID of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "region" {
  description = "US Google Cloud region hosting the cluster."
  value       = google_container_cluster.this.location
}

output "kubernetes_version" {
  description = "Current control plane Kubernetes version managed by the release channel."
  value       = google_container_cluster.this.master_version
}

output "endpoint" {
  description = "IP address or DNS endpoint of the Kubernetes API server."
  value       = google_container_cluster.this.endpoint
}

output "private_endpoint" {
  description = "Internal VPC IP address of the Kubernetes API server."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded PEM public certificate of the cluster root Certificate Authority."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "vpc_name" {
  description = "Network team VPC name used by the cluster."
  value       = local.vpc_name
}

output "subnet_name" {
  description = "Network team regional GKE subnet name used by the cluster."
  value       = local.subnet_name
}

output "workload_identity_pool" {
  description = "Workload Identity pool ('<project_id>.svc.id.goog') enabled on the cluster for authenticating Kubernetes ServiceAccounts to Google Cloud services."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Email of the dedicated least-privilege GCP service account attached to all cluster nodes."
  value       = google_service_account.nodes.email
}

output "node_pools" {
  description = "Map of logical node pool keys to their GKE node pool name, resource ID, zone locations, and Kubernetes version."
  value = {
    for key, pool in google_container_node_pool.pools : key => {
      name           = pool.name
      id             = pool.id
      node_locations = pool.node_locations
      version        = pool.version
    }
  }
}

output "workload_identity_service_accounts" {
  description = "Map of configured workload_identities keys to their GCP Service Account email and the Kubernetes ServiceAccount annotation needed by product teams."
  value = {
    for k, v in var.workload_identities : k => {
      namespace           = v.namespace
      k8s_service_account = v.k8s_service_account
      gcp_service_account = v.existing_gsa_email != null ? v.existing_gsa_email : google_service_account.workload[k].email
      ksa_annotation = {
        "iam.gke.io/gcp-service-account" = v.existing_gsa_email != null ? v.existing_gsa_email : google_service_account.workload[k].email
      }
    }
  }
}

output "get_credentials_command" {
  description = "gcloud command for platform and product engineers to configure kubectl credentials for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}
