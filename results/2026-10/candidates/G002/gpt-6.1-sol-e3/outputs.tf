output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Connection name for Cloud SQL Auth Proxy or a language connector. Use private IP and automatic IAM authentication."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private address; direct PostgreSQL connections are blocked by connector enforcement."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Names of managed application databases."
  value       = { for key, db in google_sql_database.database : key => db.name }
}

output "iam_database_usernames" {
  description = "Database usernames keyed by Google identity email (service account suffix removed). Group members log in as themselves, not as the group."
  value       = { for email, user in google_sql_user.iam : email => user.name }
}
