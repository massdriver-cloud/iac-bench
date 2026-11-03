output "instance_name" {
  description = "The name of the Cloud SQL database instance."
  value       = google_sql_database_instance.default.name
}

output "instance_self_link" {
  description = "The self-link of the Cloud SQL database instance."
  value       = google_sql_database_instance.default.self_link
}

output "connection_name" {
  description = "The connection name of the Cloud SQL instance to be used in connection strings (project:region:instance)."
  value       = google_sql_database_instance.default.connection_name
}

output "private_ip_address" {
  description = "The first private IPv4 address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.default.private_ip_address
}

output "public_ip_address" {
  description = "The first public IPv4 address assigned to the Cloud SQL instance (if enabled)."
  value       = google_sql_database_instance.default.public_ip_address
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.default.service_account_email_address
}

output "databases" {
  description = "List of database names created on the instance."
  value       = [for db in google_sql_database.databases : db.name]
}

output "built_in_users" {
  description = "List of built-in database usernames created on the instance."
  value       = [for user in google_sql_user.built_in_users : user.name]
}

output "iam_users" {
  description = "List of IAM user accounts created on the instance."
  value       = [for user in google_sql_user.iam_users : user.name]
}

output "iam_service_accounts" {
  description = "List of IAM service accounts created on the instance."
  value       = [for sa in google_sql_user.iam_service_accounts : sa.name]
}
