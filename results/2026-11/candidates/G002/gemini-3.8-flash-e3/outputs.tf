output "instance_name" {
  description = "The name of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.instance.name
}

output "instance_id" {
  description = "The ID of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.instance.id
}

output "instance_self_link" {
  description = "The URI of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.instance.self_link
}

output "connection_name" {
  description = "The connection name of the Cloud SQL instance to be used in connection strings (e.g. for Cloud SQL Auth Proxy and GKE/Compute Engine connectors)."
  value       = google_sql_database_instance.instance.connection_name
}

output "private_ip_address" {
  description = "The private IPv4 address assigned for the Cloud SQL instance, accessible from GKE and Compute Engine via Private Services Access."
  value       = google_sql_database_instance.instance.private_ip_address
}

output "database_version" {
  description = "The PostgreSQL database version of the instance."
  value       = google_sql_database_instance.instance.database_version
}

output "tier" {
  description = "The machine type / tier of the Cloud SQL instance."
  value       = google_sql_database_instance.instance.settings[0].tier
}

output "availability_type" {
  description = "The availability type of the instance ('REGIONAL' or 'ZONAL')."
  value       = google_sql_database_instance.instance.settings[0].availability_type
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance by Google."
  value       = google_sql_database_instance.instance.service_account_email_address
}

output "databases" {
  description = "Map of databases created on the instance."
  value       = { for k, db in google_sql_database.databases : k => db.name }
}

output "iam_users" {
  description = "The list of Google IAM user identities (engineers) created on the instance."
  value       = [for u in google_sql_user.iam_users : u.name]
}

output "iam_service_accounts" {
  description = "The list of Google IAM service account identities (workloads) created on the instance."
  value       = [for sa in google_sql_user.iam_service_accounts : sa.name]
}

output "additional_users" {
  description = "The list of additional user names created on the instance."
  value       = [for u in google_sql_user.additional_users : u.name]
}
