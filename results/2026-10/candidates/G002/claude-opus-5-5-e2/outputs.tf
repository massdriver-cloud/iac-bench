output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address on the apps-<environment> VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Instance self link."
  value       = google_sql_database_instance.this.self_link
}

output "databases" {
  description = "Databases created on the instance."
  value       = sort([for d in google_sql_database.this : d.name])
}

output "iam_database_users" {
  description = "Map of IAM member => PostgreSQL user name to use when logging in."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}
