output "instance_name" {
  description = "Name of the primary instance."
  value       = google_sql_database_instance.primary.name
}

output "project_id" {
  description = "Project that hosts the instance."
  value       = google_sql_database_instance.primary.project
}

output "connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy and language connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the primary on the application VPC. The instance has no public address."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "dns_name" {
  description = "Instance DNS name, usable instead of the IP address by clients that verify the server certificate."
  value       = google_sql_database_instance.primary.dns_name
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = local.private_network
}

output "database_version" {
  description = "PostgreSQL version of the instance."
  value       = google_sql_database_instance.primary.database_version
}

output "availability_type" {
  description = "Effective availability type (REGIONAL or ZONAL)."
  value       = local.availability_type
}

output "self_link" {
  description = "Self link of the primary instance."
  value       = google_sql_database_instance.primary.self_link
}

output "service_account_email" {
  description = "The instance's own service account, e.g. to grant it access to a Cloud Storage bucket for imports and exports."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "databases" {
  description = "Names of the databases managed by this module."
  value       = sort([for d in google_sql_database.this : d.name])
}

output "iam_database_users" {
  description = "IAM member => PostgreSQL user name to connect (and to GRANT privileges) as."
  value       = { for member, u in google_sql_user.iam : member => u.name }
}

output "read_replicas" {
  description = "Read replicas, keyed as in var.read_replicas."
  value = {
    for k, r in google_sql_database_instance.replica : k => {
      name               = r.name
      region             = r.region
      connection_name    = r.connection_name
      private_ip_address = r.private_ip_address
    }
  }
}

output "database_flags" {
  description = "Effective database flags (defaults, DBA overrides and enforced flags merged)."
  value       = local.database_flags
}
