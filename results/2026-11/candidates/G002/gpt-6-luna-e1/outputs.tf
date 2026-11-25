output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Cloud SQL connection name, suitable for Cloud SQL Auth Proxy/connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Instance private IP address."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_names" {
  description = "Databases created by this module."
  value       = [for database in google_sql_database.this : database.name]
}

output "iam_database_users" {
  description = "IAM database usernames created by this module."
  value       = keys(google_sql_user.iam)
}
