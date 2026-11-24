output "instance_name" {
  description = "The name of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.name
}

output "instance_connection_name" {
  description = "The connection name of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.connection_name
}

output "instance_self_link" {
  description = "The URI of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.self_link
}

output "instance_ip_address" {
  description = "The IPv4 address assigned to the instance"
  value       = google_sql_database_instance.postgres.ip_address
}

output "instance_private_ip_address" {
  description = "The private IPv4 address assigned to the instance"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "databases" {
  description = "List of created databases"
  value       = [for db in google_sql_database.dbs : db.name]
}
