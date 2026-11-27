output "instance_name" {
  value       = google_sql_database_instance.primary.name
  description = "The name of the database instance."
}

output "instance_id" {
  value       = google_sql_database_instance.primary.id
  description = "The ID of the database instance."
}

output "instance_self_link" {
  value       = google_sql_database_instance.primary.self_link
  description = "The URI of the database instance."
}

output "connection_name" {
  value       = google_sql_database_instance.primary.connection_name
  description = "The connection name of the database instance, used for Cloud SQL Auth Proxy (format: project:region:instance)."
}

output "private_ip_address" {
  value       = google_sql_database_instance.primary.private_ip_address
  description = "The first private IPv4 address assigned to the database instance."
}

output "server_ca_cert" {
  value       = google_sql_database_instance.primary.server_ca_cert
  description = "The CA certificate information for SSL/TLS verification."
  sensitive   = true
}

output "service_account_email_address" {
  value       = google_sql_database_instance.primary.service_account_email_address
  description = "The service account email address assigned to the Cloud SQL instance."
}

output "database_version" {
  value       = google_sql_database_instance.primary.database_version
  description = "The database version of the instance."
}

output "databases" {
  value       = [for db in google_sql_database.databases : db.name]
  description = "The list of databases created on the instance."
}

output "iam_users" {
  value       = [for u in google_sql_user.iam_users : u.name]
  description = "The list of IAM user identities configured on the instance."
}

output "iam_service_accounts" {
  value       = [for u in google_sql_user.iam_service_accounts : u.name]
  description = "The list of IAM service account identities configured on the instance."
}

output "iam_groups" {
  value       = [for u in google_sql_user.iam_groups : u.name]
  description = "The list of IAM group identities configured on the instance."
}

output "read_replicas" {
  value = {
    for k, v in google_sql_database_instance.replicas : k => {
      name               = v.name
      connection_name    = v.connection_name
      private_ip_address = v.private_ip_address
    }
  }
  description = "Map of read replicas and their connection details."
}
