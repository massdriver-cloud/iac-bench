output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) used by clients and the Cloud SQL Auth Proxy."
  value       = "${var.project}:${var.region}:${google_sql_database_instance.this.name}"
}

output "private_ip_address" {
  description = "Private IP address, reachable from apps-<environment> and anything peered with it."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Self link of the instance."
  value       = google_sql_database_instance.this.self_link
}

output "instance_service_account" {
  description = "The instance's own service account, e.g. for granting it access to a CMEK key."
  value       = google_sql_database_instance.this.service_account_email_address
}
