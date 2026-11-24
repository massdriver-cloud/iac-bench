output "instance_name" {
  description = "The name of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "The connection name of the Cloud SQL instance (`project:region:instance`) for use with Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "self_link" {
  description = "The URI of the created Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "private_ip_address" {
  description = "The private IPv4 address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.this.private_ip_address
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "network" {
  description = "The VPC network self-link to which the Cloud SQL instance is connected."
  value       = local.network_id
}

output "databases" {
  description = "Names of databases created on the Cloud SQL instance."
  value       = [for db in google_sql_database.databases : db.name]
}

output "iam_users" {
  description = "Map of IAM database users registered on the Cloud SQL instance."
  value       = { for k, u in google_sql_user.iam_users : k => u.name }
}
