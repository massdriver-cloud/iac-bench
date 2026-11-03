output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Instance connection name (project:region:name), used by the Cloud SQL proxy."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private IPv4 address of the instance."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "public_ip_address" {
  description = "Public IPv4 address of the instance (empty when ipv4_enabled is false)."
  value       = google_sql_database_instance.postgres.public_ip_address
}

output "self_link" {
  description = "Self link of the instance."
  value       = google_sql_database_instance.postgres.self_link
}

output "service_account_email_address" {
  description = "Service account email address used by the instance."
  value       = google_sql_database_instance.postgres.service_account_email_address
}