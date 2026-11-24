output "instance_name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Connection name of the primary instance (project:region:instance) for Cloud SQL Auth Proxy and IAM authentication."
  value       = google_sql_database_instance.primary.connection_name
}

output "self_link" {
  description = "Self link of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "private_ip_address" {
  description = "Private IPv4 address of the primary Cloud SQL instance on the environment VPC network."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "dns_name" {
  description = "Private DNS name of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.dns_name
}

output "service_account_email_address" {
  description = "GCP service account email associated with the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "vpc_network" {
  description = "Self link of the environment VPC network attached to the instance."
  value       = local.vpc_network_self_link
}

output "databases" {
  description = "Names of the logical databases created on the instance."
  value       = [for db in google_sql_database.databases : db.name]
}

output "iam_users" {
  description = "Map of IAM database users configured on the instance."
  value = {
    for k, u in google_sql_user.iam_users : k => {
      name = u.name
      type = u.type
    }
  }
}

output "read_replicas" {
  description = "Connection details for any read replica instances."
  value = {
    for k, r in google_sql_database_instance.read_replicas : k => {
      name               = r.name
      connection_name    = r.connection_name
      private_ip_address = r.private_ip_address
    }
  }
}
