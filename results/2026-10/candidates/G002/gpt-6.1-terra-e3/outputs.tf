output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Connection name for the Cloud SQL Auth Proxy or connectors."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private IP address for clients on connected networks."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Application databases managed by this configuration."
  value       = [for db in google_sql_database.databases : db.name]
}
