output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "PROJECT:REGION:INSTANCE identifier for the Cloud SQL Auth Proxy or language connectors. Configure private IP and automatic IAM authentication."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private endpoint. Direct connections are blocked by connector enforcement."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Application databases managed by this root module."
  value       = [for database in google_sql_database.application : database.name]
}

output "iam_database_usernames" {
  description = "Identity email to PostgreSQL username; service account usernames omit .gserviceaccount.com. Group members log in with their own identity, not the group name."
  value       = { for email, user in google_sql_user.iam : email => user.name }
}
