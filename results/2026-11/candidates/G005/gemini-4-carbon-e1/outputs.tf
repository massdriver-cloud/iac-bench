output "cluster_id" {
  description = "Fully qualified GKE cluster resource ID (projects/<project>/locations/<region>/clusters/<name>)."
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Region in which the regional GKE cluster control plane and node pools run."
  value       = google_container_cluster.this.location
}

output "master_version" {
  description = "Current Kubernetes version running on the GKE control plane."
  value       = google_container_cluster.this.master_version
}

output "endpoint" {
  description = "IP address/DNS endpoint of the Kubernetes API server."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate bundle used to verify the Kubernetes API server."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "network" {
  description = "Self-link path of the shared environment VPC hosting the cluster."
  value       = local.network_self_link
}

output "subnetwork" {
  description = "Self-link path of the regional GKE subnet (<vpc>-gke-<region>) hosting the cluster."
  value       = local.subnetwork_self_link
}

output "workload_identity_pool" {
  description = "Workload Identity Federation pool (<project_id>.svc.id.goog) used by pods to authenticate to Google Cloud services."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Email of the dedicated least-privilege Google Service Account attached to worker nodes."
  value       = google_service_account.nodes.email
}

output "node_network_tags" {
  description = "Base Compute Engine network tags applied to all cluster nodes for VPC firewall rules."
  value       = local.base_network_tags
}

output "node_pool_names" {
  description = "Names of all managed GKE node pools (including the dedicated system pool when enabled)."
  value = concat(
    [for np in google_container_node_pool.system : np.name],
    sort(keys(google_container_node_pool.workload)),
  )
}

output "workload_identities" {
  description = "Details for each configured Workload Identity entry, including the Google Service Account email and the annotation to place on the Kubernetes ServiceAccount."
  value = {
    for k, wi in var.workload_identities : k => {
      namespace                = wi.namespace
      ksa_name                 = wi.ksa_name
      gcp_service_account      = local.workload_identity_gsa_emails[k]
      ksa_annotation           = { "iam.gke.io/gcp-service-account" = local.workload_identity_gsa_emails[k] }
      workload_identity_member = "serviceAccount:${local.workload_identity_pool}[${wi.namespace}/${wi.ksa_name}]"
    }
  }
}

output "get_credentials_command" {
  description = "gcloud command for platform engineers to configure kubeconfig for this cluster."
  value = join(" ", compact([
    "gcloud container clusters get-credentials",
    var.name,
    "--region=${var.region}",
    "--project=${var.project_id}",
    var.enable_private_endpoint ? "--internal-ip" : "",
  ]))
}
