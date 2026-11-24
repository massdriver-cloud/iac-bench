output "instance_name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Cloud SQL connection name (<project>:<region>:<instance>) for Auth Proxy and language connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IPv4 address of the primary instance within the environment VPC."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "self_link" {
  description = "Self-link URI of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "service_account_email_address" {
  description = "Google-managed service account email for the primary Cloud SQL instance (used for GCS imports/exports or CMEK)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "vpc_network" {
  description = "VPC network resource ID attached to the instance via private services access."
  value       = data.google_compute_network.vpc.id
}

output "database_version" {
  description = "PostgreSQL version running on the instance."
  value       = google_sql_database_instance.primary.database_version
}

output "tier" {
  description = "Machine tier configured on the primary instance."
  value       = local.tier
}

output "availability_type" {
  description = "Availability type ('REGIONAL' or 'ZONAL') configured on the primary instance."
  value       = local.availability_type
}

output "deletion_protection" {
  description = "Whether deletion protection is enabled on the instance."
  value       = local.deletion_protection
}

output "databases" {
  description = "List of managed application database names created on the primary instance."
  value       = keys(google_sql_database.databases)
}

output "iam_users" {
  description = "Map of provisioned Cloud SQL IAM user identifiers and their types."
  value = {
    for k, u in google_sql_user.iam_users : k => {
      name = u.name
      type = u.type
    }
  }
}

output "effective_database_flags" {
  description = "Effective PostgreSQL database flags applied to the primary instance."
  value       = local.effective_database_flags
}

output "read_replicas" {
  description = "Map of read replica connection names and private IP addresses."
  value = {
    for k, r in google_sql_database_instance.read_replicas : k => {
      instance_name      = r.name
      connection_name    = r.connection_name
      private_ip_address = r.private_ip_address
      region             = r.region
    }
  }
}
