output "instance_name" {
  description = "The name of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.main.name
}

output "instance_id" {
  description = "The instance ID for the Cloud SQL instance."
  value       = google_sql_database_instance.main.id
}

output "instance_self_link" {
  description = "The URI of the Cloud SQL instance."
  value       = google_sql_database_instance.main.self_link
}

output "connection_name" {
  description = "The connection name of the instance to be used in connection strings or Cloud SQL Proxy (format: project:region:instance)."
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip_address" {
  description = "The first private IPv4 address assigned for the Cloud SQL instance."
  value       = google_sql_database_instance.main.private_ip_address
}

output "server_ca_cert" {
  description = "The CA certificate information for SSL/TLS validation."
  value       = google_sql_database_instance.main.server_ca_cert
  sensitive   = true
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.main.service_account_email_address
}

output "database_version" {
  description = "The database engine version running on the instance."
  value       = google_sql_database_instance.main.database_version
}

output "tier" {
  description = "The compute tier of the instance."
  value       = google_sql_database_instance.main.settings[0].tier
}

output "availability_type" {
  description = "The availability type configured on the instance (REGIONAL or ZONAL)."
  value       = google_sql_database_instance.main.settings[0].availability_type
}

output "database_names" {
  description = "List of databases created on the instance."
  value       = [for db in google_sql_database.databases : db.name]
}

output "iam_users" {
  description = "List of IAM user emails granted database authentication."
  value       = [for u in google_sql_user.iam_users : u.name]
}

output "iam_service_accounts" {
  description = "List of IAM service account emails granted database authentication."
  value       = [for sa in google_sql_user.iam_service_accounts : sa.name]
}

output "primary_network" {
  description = "The VPC network to which the instance is privately connected."
  value       = local.private_network
}
