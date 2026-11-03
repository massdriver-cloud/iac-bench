output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Instance self link."
  value       = google_sql_database_instance.this.self_link
}

output "databases" {
  description = "Names of databases created by the module."
  value       = [for d in google_sql_database.this : d.name]
}

output "iam_users" {
  description = "Database login names created for IAM identities."
  value       = [for u in google_sql_user.iam : u.name]
}
