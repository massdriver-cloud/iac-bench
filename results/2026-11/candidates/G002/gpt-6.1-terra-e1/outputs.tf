output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Instance connection name for Cloud SQL connectors."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private IP address for direct private network connections."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Managed application databases."
  value       = [for database in google_sql_database.database : database.name]
}
