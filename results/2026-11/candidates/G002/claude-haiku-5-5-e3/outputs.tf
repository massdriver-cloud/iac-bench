output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "Connection name (project:region:instance) used by the Cloud SQL Auth Proxy and connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance inside the apps-<environment> VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "databases" {
  description = "Names of the databases created on the instance."
  value       = keys(google_sql_database.this)
}

output "iam_database_users" {
  description = "IAM database user names granted login, keyed by Google identity email."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}
