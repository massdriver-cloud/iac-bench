output "instance_name" {
  description = "The name of the database instance."
  value       = google_sql_database_instance.postgres.name
}

output "instance_id" {
  description = "The ID of the database instance."
  value       = google_sql_database_instance.postgres.id
}

output "connection_name" {
  description = "The connection name of the instance to be used in connection strings (project:region:instance)."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "The first private IPv4 address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "instance_self_link" {
  description = "The URI of the instance."
  value       = google_sql_database_instance.postgres.self_link
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.postgres.service_account_email_address
}

output "database_version" {
  description = "The database version of the instance."
  value       = google_sql_database_instance.postgres.database_version
}

output "environment" {
  description = "The deployment environment of the instance."
  value       = local.normalized_environment
}

output "network" {
  description = "The VPC network the instance is connected to."
  value       = local.network_link
}

output "databases" {
  description = "Map of created databases and their configurations."
  value = {
    for k, db in google_sql_database.databases : k => {
      name      = db.name
      charset   = db.charset
      collation = db.collation
    }
  }
}

output "iam_users" {
  description = "List of IAM database users created for engineers."
  value       = [for u in google_sql_user.iam_users : u.name]
}

output "iam_service_accounts" {
  description = "List of IAM database service accounts created for workloads."
  value       = [for u in google_sql_user.iam_service_accounts : u.name]
}
