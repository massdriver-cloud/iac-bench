output "cluster_id" {
  description = "Fully qualified Google Cloud resource ID of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE Standard cluster."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Region hosting the regional GKE control plane."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "IP address or DNS endpoint of the Kubernetes API server."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate used to verify the Kubernetes API server."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "master_version" {
  description = "Current Kubernetes control plane version running on the cluster."
  value       = google_container_cluster.this.master_version
}

output "network" {
  description = "VPC network self-link path used by the cluster."
  value       = local.network_self_link
}

output "subnetwork" {
  description = "Regional GKE subnet self-link path used by the cluster."
  value       = local.subnetwork_self_link
}

output "workload_identity_pool" {
  description = "Workload Identity pool used by Kubernetes ServiceAccounts to federate into Google Cloud IAM."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Email of the dedicated least-privilege GCP service account attached to cluster worker nodes."
  value       = google_service_account.nodes.email
}

output "node_pools" {
  description = "Summary of managed GKE Standard node pools keyed by pool name."
  value = {
    for name, pool in google_container_node_pool.this : name => {
      id              = pool.id
      version         = pool.version
      machine_type    = pool.node_config[0].machine_type
      spot            = pool.node_config[0].spot
      node_locations  = pool.node_locations
      min_nodes       = pool.autoscaling[0].total_min_node_count
      max_nodes       = pool.autoscaling[0].total_max_node_count
      instance_groups = pool.managed_instance_group_urls
    }
  }
}

output "workload_identity_service_accounts" {
  description = "Map of configured workload_identities keys to the bound GCP service account email and Kubernetes IAM annotation value."
  value = {
    for k, wi in var.workload_identities : k => {
      namespace           = wi.namespace
      k8s_service_account = wi.k8s_service_account
      gcp_service_account_email = (
        wi.gcp_service_account_email != null
        ? wi.gcp_service_account_email
        : google_service_account.workload[k].email
      )
      k8s_annotation = {
        "iam.gke.io/gcp-service-account" = (
          wi.gcp_service_account_email != null
          ? wi.gcp_service_account_email
          : google_service_account.workload[k].email
        )
      }
    }
  }
}

output "kubectl_credentials_command" {
  description = "Ready-to-run gcloud command for platform and product engineers to configure kubeconfig for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}
