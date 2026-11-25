output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_id" {
  value = google_container_cluster.this.id
}

output "endpoint" {
  value = google_container_cluster.this.endpoint
}

output "ca_certificate" {
  value     = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "workload_identity_pool" {
  description = "Use as principal prefix: serviceAccount:<pool>[ns/ksa] or principal://.../subject/ns/<ns>/sa/<ksa> for IAM grants."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  value = google_service_account.nodes.email
}
