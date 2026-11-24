output "connection_name" {
  description = "Project:region:instance identifier for Cloud SQL connectors."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private database endpoint in the application VPC."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.postgres.name
}
