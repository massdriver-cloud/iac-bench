output "instance_name" {
  description = "Cloud SQL instance ID."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Project:region:instance identifier for Cloud SQL connectors and the Auth Proxy."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private services access address. Connections must still use a Cloud SQL connector."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Names of the databases managed by this module (not including built-in databases)."
  value       = keys(google_sql_database.database)
}

output "iam_login_names" {
  description = "Cloud SQL IAM usernames keyed by full identity email. Group members log in as themselves, not as the group."
  value       = { for email, user in google_sql_user.iam : email => user.name }
}
