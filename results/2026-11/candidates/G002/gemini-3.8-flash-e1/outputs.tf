output "instance_name" {
  description = "The name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "instance_id" {
  description = "The ID of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.id
}

output "instance_self_link" {
  description = "The URI of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "connection_name" {
  description = "The connection name of the primary instance to be used in connection strings or Cloud SQL Auth Proxy (format: project:region:instance)."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "The primary private IPv4 address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "database_version" {
  description = "The PostgreSQL version running on the instance."
  value       = google_sql_database_instance.primary.database_version
}

output "service_account_email_address" {
  description = "The service account email address assigned as the Cloud SQL instance identity."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "server_ca_cert" {
  description = "The CA certificate information for SSL/TLS validation."
  value       = google_sql_database_instance.primary.server_ca_cert
  sensitive   = true
}

output "environment" {
  description = "The environment the instance is deployed in."
  value       = local.clean_environment
}

output "network" {
  description = "The VPC network self-link connected to the instance."
  value       = local.network_link
}

output "databases" {
  description = "Map of databases created on the instance."
  value = {
    for k, db in google_sql_database.databases : k => db.name
  }
}

output "iam_users" {
  description = "List of engineer Google identity emails configured as Cloud IAM users."
  value       = [for u in google_sql_user.iam_users : u.name]
}

output "iam_service_accounts" {
  description = "List of workload service account identities configured as Cloud IAM service accounts."
  value       = [for sa in google_sql_user.iam_service_accounts : sa.name]
}

output "read_replicas" {
  description = "Map of read replicas created, including their connection names and private IP addresses."
  value = {
    for k, r in google_sql_database_instance.replicas : k => {
      name               = r.name
      connection_name    = r.connection_name
      private_ip_address = r.private_ip_address
    }
  }
}
