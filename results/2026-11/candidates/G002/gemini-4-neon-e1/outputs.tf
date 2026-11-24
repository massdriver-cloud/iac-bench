output "instance_name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "instance_id" {
  description = "Resource ID of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.id
}

output "instance_self_link" {
  description = "Self-link URI of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance) for Cloud SQL Auth Proxy and Language Connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private VPC IP address of the primary instance."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "dns_name" {
  description = "Cloud SQL DNS name of the primary instance."
  value       = google_sql_database_instance.primary.dns_name
}

output "region" {
  description = "GCP region where the primary instance is deployed."
  value       = google_sql_database_instance.primary.region
}

output "environment" {
  description = "Environment of the instance (dev, staging, or prod)."
  value       = var.environment
}

output "network" {
  description = "VPC network resource ID to which the instance is connected via Private Services Access."
  value       = data.google_compute_network.vpc.id
}

output "service_account_email_address" {
  description = "GCP service account email created by Cloud SQL for this instance (used for GCS import/export and CMEK KMS permissions)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "server_ca_cert" {
  description = "Server CA certificate for verifying TLS connections to the primary instance."
  value       = google_sql_database_instance.primary.server_ca_cert
  sensitive   = true
}

output "databases" {
  description = "Managed logical PostgreSQL databases on the primary instance."
  value = {
    for name, db in google_sql_database.databases : name => {
      name      = db.name
      self_link = db.self_link
      charset   = db.charset
      collation = db.collation
    }
  }
}

output "iam_users" {
  description = "Cloud SQL IAM user principals configured on the instance."
  value       = sort(keys(google_sql_user.iam_users))
}

output "iam_service_accounts" {
  description = "Map of GCP service account emails to their Cloud SQL IAM database usernames."
  value       = local.iam_service_account_usernames
}

output "iam_groups" {
  description = "Cloud SQL IAM group principals configured on the instance."
  value       = sort(keys(google_sql_user.iam_groups))
}

output "read_replicas" {
  description = "Connection and metadata details for each read replica."
  value = {
    for key, replica in google_sql_database_instance.read_replica : key => {
      instance_name                 = replica.name
      connection_name               = replica.connection_name
      private_ip_address            = replica.private_ip_address
      dns_name                      = replica.dns_name
      region                        = replica.region
      service_account_email_address = replica.service_account_email_address
    }
  }
}
