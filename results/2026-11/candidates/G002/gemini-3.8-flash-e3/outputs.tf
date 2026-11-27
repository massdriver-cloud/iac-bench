###############################################################################
# Primary Instance Outputs
###############################################################################

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
  description = "The connection name of the instance to be used in connection strings or Cloud SQL Auth Proxy (format: project:region:instance)."
  value       = google_sql_database_instance.instance.connection_name
}

output "private_ip_address" {
  description = "The private IPv4 address assigned to the Cloud SQL instance within the VPC network."
  value       = google_sql_database_instance.instance.private_ip_address
}

output "server_ca_cert" {
  description = "The CA certificate information used to verify the server certificate during SSL connections."
  value       = google_sql_database_instance.instance.server_ca_cert
  sensitive   = true
}

output "database_version" {
  description = "The PostgreSQL version running on the instance."
  value       = google_sql_database_instance.instance.database_version
}

output "region" {
  description = "The Google Cloud region of the Cloud SQL instance."
  value       = google_sql_database_instance.instance.region
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance by GCP."
  value       = google_sql_database_instance.instance.service_account_email_address
}

###############################################################################
# Databases and Identity Outputs
###############################################################################

output "databases" {
  description = "The names of all databases created on the instance."
  value       = [for db in google_sql_database.databases : db.name]
}

output "iam_users" {
  description = "The names of all Cloud IAM users created on the instance."
  value       = [for u in google_sql_user.iam_users : u.name]
}

output "iam_service_accounts" {
  description = "The names of all Cloud IAM service accounts created on the instance."
  value       = [for sa in google_sql_user.iam_service_accounts : sa.name]
}

###############################################################################
# Read Replica Outputs
###############################################################################

output "read_replicas" {
  description = "Map of created read replicas with their connection names and private IP addresses."
  value = {
    for k, replica in google_sql_database_instance.read_replicas : k => {
      name               = replica.name
      connection_name    = replica.connection_name
      private_ip_address = replica.private_ip_address
    }
  }
}
