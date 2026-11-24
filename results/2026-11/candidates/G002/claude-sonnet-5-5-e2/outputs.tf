output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL connectors and auth proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance in the environment VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "network" {
  description = "VPC the instance is attached to."
  value       = local.network
}

output "database_names" {
  description = "Databases created on the instance."
  value       = [for d in google_sql_database.this : d.name]
}

output "iam_database_users" {
  description = "IAM database user names created on the instance."
  value       = [for u in google_sql_user.iam : u.name]
}
