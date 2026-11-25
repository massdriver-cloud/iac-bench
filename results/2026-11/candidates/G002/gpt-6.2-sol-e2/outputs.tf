output "instance_name" {
  description = "Cloud SQL instance ID."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "PROJECT:REGION:INSTANCE connection name for Cloud SQL connectors."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private endpoint for direct TLS connections from the application network."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Names of application databases managed by this root."
  value       = sort(keys(google_sql_database.database))
}

output "iam_database_usernames" {
  description = "PostgreSQL login name for each configured IAM principal, keyed by its full IAM member string."
  value       = { for member, user in google_sql_user.iam : member => user.name }
}
