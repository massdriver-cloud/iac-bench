output "instance_name" {
  description = "Cloud SQL instance ID."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Cloud SQL connector connection name (project:region:instance)."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private IP address for clients with VPC connectivity."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Managed databases."
  value       = { for key, database in google_sql_database.database : key => database.name }
}

output "iam_database_usernames" {
  description = "Cloud SQL PostgreSQL usernames for the managed IAM identities."
  value       = { for key, user in google_sql_user.iam : key => user.name }
}
