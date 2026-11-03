output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Cloud SQL connection name for Cloud SQL Auth Proxy/connectors."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private IP address assigned to the instance."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  description = "Name of the database created by this module."
  value       = google_sql_database.default.name
}
