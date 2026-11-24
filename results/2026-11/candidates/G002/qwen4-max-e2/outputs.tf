output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP of the instance inside the apps VPC. Applications connect here on port 5432."
  value       = google_sql_database_instance.this.private_ip_address
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = data.google_compute_network.apps.name
}

output "service_account_email_address" {
  description = "Service account email of the instance (used when granting it access to other resources)."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "databases" {
  description = "Additional databases created on the instance."
  value       = [for db in google_sql_database.this : db.name]
}
