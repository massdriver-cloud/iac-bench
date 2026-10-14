output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL connectors and Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance."
  value       = google_sql_database_instance.this.private_ip_address
}
