output "instance_name" {
  value       = google_sql_database_instance.default.name
  description = "The name of the Cloud SQL instance."
}

output "instance_self_link" {
  value       = google_sql_database_instance.default.self_link
  description = "The URI of the Cloud SQL instance."
}

output "connection_name" {
  value       = google_sql_database_instance.default.connection_name
  description = "The connection name of the Cloud SQL instance to be used in connection strings or Proxy."
}

output "private_ip_address" {
  value       = google_sql_database_instance.default.private_ip_address
  description = "The private IP address assigned to the Cloud SQL instance."
}

output "public_ip_address" {
  value       = google_sql_database_instance.default.public_ip_address
  description = "The public IP address assigned to the Cloud SQL instance, if enabled."
}

output "service_account_email_address" {
  value       = google_sql_database_instance.default.service_account_email_address
  description = "The service account email address assigned to the Cloud SQL instance."
}

output "databases" {
  value       = google_sql_database.databases
  description = "Map of created database resources."
}

output "iam_users" {
  value       = google_sql_user.iam_users
  description = "Map of created IAM user resources."
}

output "iam_service_accounts" {
  value       = google_sql_user.iam_service_accounts
  description = "Map of created IAM service account user resources."
}

output "db_users" {
  value       = google_sql_user.db_users
  description = "Map of created built-in database user resources."
  sensitive   = true
}
