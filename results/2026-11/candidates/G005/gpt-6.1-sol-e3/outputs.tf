output "cluster_id" {
  description = "Fully qualified regional GKE cluster ID."
  value       = google_container_cluster.this.id
}

output "cluster_name" { value = google_container_cluster.this.name }
output "location" { value = google_container_cluster.this.location }
output "private_endpoint" {
  description = "Private control-plane address; reachable only via configured private connectivity and authorized source networks."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}
output "workload_pool" { value = "${var.project_id}.svc.id.goog" }
output "node_service_account" { value = google_service_account.nodes.email }
output "workload_service_accounts" {
  description = "Annotate each Kubernetes SA with iam.gke.io/gcp-service-account using the corresponding email. Kubernetes resources are deliberately not managed here."
  value = { for key, identity in var.workload_identities : key => {
    namespace       = identity.namespace
    service_account = identity.service_account
    google_email    = google_service_account.workload[key].email
    annotation      = { "iam.gke.io/gcp-service-account" = google_service_account.workload[key].email }
  } }
}
output "get_credentials_command" {
  description = "Run from an authorized private network with gcloud and gke-gcloud-auth-plugin installed."
  value       = "gcloud container clusters get-credentials ${var.name} --region ${var.region} --project ${var.project_id} --internal-ip"
}
