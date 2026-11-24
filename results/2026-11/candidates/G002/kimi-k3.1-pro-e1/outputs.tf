output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Cloud SQL connection name for Auth Proxy and language connectors (PROJECT:REGION:INSTANCE)."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address applications use through the environment VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "database_version" {
  description = "Configured PostgreSQL version."
  value       = google_sql_database_instance.this.database_version
}

output "availability_type" {
  description = "Effective availability policy, including the environment-based default."
  value       = local.availability_type
}

output "database_names" {
  description = "Names of additional databases managed by this module."
  value       = sort(keys(google_sql_database.this))
}

output "iam_database_users" {
  description = "Map of IAM identity email addresses to their Cloud SQL IAM user type."
  value       = { for identity, user in google_sql_user.iam : identity => user.type }
}

output "effective_database_flags" {
  description = "Effective PostgreSQL flags, including mandatory IAM authentication."
  value       = local.database_flags
}
