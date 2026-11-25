locals {
  # A ready-to-use kubeconfig for the cluster. Authentication goes through
  # gke-gcloud-auth-plugin, which needs no static credentials to be stored in
  # this file (only the public CA certificate is included).
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"

    clusters = [{
      name = local.cluster_name
      cluster = {
        server                       = "https://${google_container_cluster.this.endpoint}"
        "certificate-authority-data" = google_container_cluster.this.master_auth[0].cluster_ca_certificate
      }
    }]

    users = [{
      name = local.cluster_name
      user = {
        exec = {
          apiVersion         = "client.authentication.k8s.io/v1beta1"
          command            = "gke-gcloud-auth-plugin"
          interactiveMode    = "Never"
          provideClusterInfo = true
        }
      }
    }]

    contexts = [{
      name = local.cluster_name
      context = {
        cluster = local.cluster_name
        user    = local.cluster_name
      }
    }]

    "current-context" = local.cluster_name
  })
}

output "cluster_name" {
  description = "Name of the cluster."
  value       = local.cluster_name
}

output "cluster_id" {
  description = "Fully qualified id of the cluster."
  value       = google_container_cluster.this.id
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the control plane. A private address when enable_private_endpoint is true."
  value       = "https://${google_container_cluster.this.endpoint}"
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the control plane, for building kubeconfigs."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "kubeconfig" {
  description = "A complete kubeconfig file for the cluster, authenticating via gke-gcloud-auth-plugin. Write it with: tofu output -raw kubeconfig > kubeconfig.yaml"
  value       = local.kubeconfig
  sensitive   = true
}

output "get_credentials_command" {
  description = "gcloud command that configures kubectl for this cluster (run from a machine that can reach the endpoint)."
  value       = "gcloud container clusters get-credentials ${local.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "workload_identity_pool" {
  description = "Workload Identity pool of the cluster. Bind Kubernetes service accounts to Google IAM through it, using the member form <pool>[/<namespace>/<k8s-service-account>]."
  value       = local.workload_identity_pool
}

output "node_service_account_email" {
  description = "Service account the cluster's nodes run as."
  value       = local.node_service_account_email
}

output "node_pool_names" {
  description = "Names of the node pools managed by this module."
  value       = concat([for name, pool in google_container_node_pool.workload : name], var.create_system_node_pool ? ["system"] : [])
}

output "control_plane_version" {
  description = "Kubernetes version currently running on the control plane."
  value       = google_container_cluster.this.master_version
}
