output "cluster_name" {
  description = "Name of the cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Full resource ID of the cluster."
  value       = google_container_cluster.this.id
}

output "project_id" {
  description = "Project the cluster is in."
  value       = local.project_id
}

output "region" {
  description = "Region the cluster is in."
  value       = google_container_cluster.this.location
}

output "network" {
  description = "VPC the cluster is attached to."
  value       = local.network
}

output "subnetwork" {
  description = "Subnet the cluster's nodes are in."
  value       = local.subnetwork
}

output "release_channel" {
  description = "Release channel the cluster follows."
  value       = local.release_channel
}

output "get_credentials_command" {
  description = "Command that configures kubectl for this cluster through the IAM-authenticated DNS endpoint."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${local.project_id} --dns-endpoint"
}

output "dns_endpoint" {
  description = "DNS-based control plane endpoint (IAM-authenticated)."
  value       = try(google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint, null)
}

output "private_endpoint" {
  description = "Private IP endpoint of the control plane, reachable only from the cluster subnet and authorized internal ranges."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the control plane (needed with the private IP endpoint)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool. Grant a workload access to a Google Cloud service by giving an IAM role to principal://iam.googleapis.com/projects/<project-number>/locations/global/workloadIdentityPools/<this value>/subject/ns/<namespace>/sa/<kubernetes-service-account>."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account_email" {
  description = "Service account the nodes run as. Grant it roles/artifactregistry.reader on image repositories that live in other projects."
  value       = google_service_account.nodes.email
}

output "node_network_tag" {
  description = "Network tag on every node of this cluster, for firewall rules."
  value       = local.node_network_tag
}

output "node_pool_names" {
  description = "Names of the node pools."
  value       = sort([for p in google_container_node_pool.this : p.name])
}
