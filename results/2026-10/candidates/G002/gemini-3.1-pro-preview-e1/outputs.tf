output "instance_name" {
  description = "The name of the database instance"
  value       = google_sql_database_instance.main.name
}

output "instance_connection_name" {
  description = "The connection name of the instance to be used in connection strings"
  value       = google_sql_database_instance.main.connection_name
}

output "instance_private_ip_address" {
  description = "The IPv4 address assigned to the instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "instance_self_link" {
  description = "The URI of the instance"
  value       = google_sql_database_instance.main.self_link
}
