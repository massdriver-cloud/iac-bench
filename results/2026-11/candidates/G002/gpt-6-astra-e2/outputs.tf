output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "project:region:instance identifier for the Cloud SQL Auth Proxy or language connectors. Use private IP and automatic IAM authentication."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private PostgreSQL endpoint reachable from the selected VPC."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "private_network" {
  description = "Existing VPC used by the instance."
  value       = local.private_network
}

output "database_names" {
  description = "Managed database names."
  value       = { for name, database in google_sql_database.databases : name => database.name }
}

output "iam_database_usernames" {
  description = "Identity email to SQL username; service account SQL usernames omit .gserviceaccount.com. Group members log in using their own identity, not the group name."
  value       = { for email, user in google_sql_user.iam : email => user.name }
}
