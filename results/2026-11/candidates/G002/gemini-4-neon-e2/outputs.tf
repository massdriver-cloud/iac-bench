output "instance_name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance) for Cloud SQL Auth Proxy and Language Connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private VPC IP address of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "self_link" {
  description = "GCP self-link of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "service_account_email_address" {
  description = "GCP service account email associated with the primary Cloud SQL instance (for GCS import/export or KMS permissions)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "server_ca_cert" {
  description = "Server CA certificate for verifying TLS connections to the primary instance."
  value       = google_sql_database_instance.primary.server_ca_cert
  sensitive   = true
}

output "network" {
  description = "VPC network resolved for this environment."
  value = {
    name = data.google_compute_network.vpc.name
    id   = data.google_compute_network.vpc.id
  }
}

output "databases" {
  description = "Names of the managed logical databases created on the primary instance."
  value       = sort(keys(google_sql_database.databases))
}

output "iam_database_users" {
  description = "Map of Google IAM member identifiers to their provisioned PostgreSQL usernames and user types."
  value = {
    for k, u in google_sql_user.iam : k => {
      username = u.name
      type     = u.type
    }
  }
}

output "read_replicas" {
  description = "Connection details for each provisioned read replica."
  value = {
    for k, r in google_sql_database_instance.read_replica : k => {
      instance_name                 = r.name
      connection_name               = r.connection_name
      private_ip_address            = r.private_ip_address
      region                        = r.region
      self_link                     = r.self_link
      service_account_email_address = r.service_account_email_address
    }
  }
}

output "effective_configuration" {
  description = "Summary of the effective standardized and environment-derived settings applied to the primary instance."
  value = {
    environment                    = var.environment
    region                         = local.region
    database_version               = var.database_version
    edition                        = var.edition
    tier                           = local.tier
    availability_type              = local.availability_type
    disk_size_gb                   = local.disk_size
    disk_type                      = var.disk_type
    retained_backups               = local.retained_backups
    transaction_log_retention_days = local.transaction_log_retention_days
    maintenance_update_track       = local.maintenance_update_track
    deletion_protection            = local.deletion_protection
    retain_backups_on_delete       = local.retain_backups_on_delete
    effective_database_flags       = local.effective_database_flags
  }
}
