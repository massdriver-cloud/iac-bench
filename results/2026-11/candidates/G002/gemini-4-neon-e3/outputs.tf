output "instance_name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance) for Cloud SQL Auth Proxy and Language Connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IPv4 address of the primary instance inside the environment VPC."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "self_link" {
  description = "Self link of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "service_account_email_address" {
  description = "Google-managed service account email for the primary Cloud SQL instance (used for GCS imports/exports and CMEK permissions)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "server_ca_cert" {
  description = "Server CA certificate for the primary instance (for clients verifying TLS with sslmode=verify-ca)."
  value       = google_sql_database_instance.primary.server_ca_cert
  sensitive   = true
}

output "region" {
  description = "GCP region where the primary instance is deployed."
  value       = google_sql_database_instance.primary.region
}

output "vpc_network_id" {
  description = "Resource ID of the VPC network attached via private services access."
  value       = data.google_compute_network.vpc.id
}

output "databases" {
  description = "Names of the PostgreSQL databases managed by this module."
  value       = sort(keys(google_sql_database.this))
}

output "iam_users" {
  description = "Google user emails configured with CLOUD_IAM_USER access."
  value       = sort(keys(google_sql_user.iam_user))
}

output "iam_service_account_usernames" {
  description = "Map of Google service account emails to their Cloud SQL PostgreSQL usernames (without the .gserviceaccount.com suffix)."
  value       = { for email, user in google_sql_user.iam_service_account : email => user.name }
}

output "iam_groups" {
  description = "Google Group emails configured with CLOUD_IAM_GROUP access."
  value       = sort(keys(google_sql_user.iam_group))
}

output "read_replicas" {
  description = "Map of read replica connection details keyed by replica suffix."
  value = {
    for k, replica in google_sql_database_instance.read_replica : k => {
      instance_name      = replica.name
      connection_name    = replica.connection_name
      private_ip_address = replica.private_ip_address
      region             = replica.region
      self_link          = replica.self_link
    }
  }
}
