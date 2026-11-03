output "instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Connection name used by Cloud SQL Proxy / private IP clients."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "service_account_email" {
  description = "Service account that runs the instance (useful for IAM binding grants)."
  value       = google_sql_database_instance.postgres.service_account_email_address
}

output "database_name" {
  description = "Name of the application database."
  value       = google_sql_database.app.name
}

output "iam_users" {
  description = "Map of PostgreSQL user -> Google identity email."
  value       = { for k, v in var.users : k => v }
}