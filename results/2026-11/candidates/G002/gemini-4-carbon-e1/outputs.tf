output "instance_name" {
  description = "Name of the primary Cloud SQL for PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Cloud SQL connection name ('project:region:instance') for Cloud SQL Auth Proxy and Language Connectors on GKE and Compute Engine."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IPv4 address of the primary instance on the environment VPC network."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "dns_name" {
  description = "Private DNS name of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.dns_name
}

output "self_link" {
  description = "Self-link URI of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "service_account_email" {
  description = "Google-managed service account email for the primary Cloud SQL instance (used for CMEK KMS key grants or Cloud Storage import/export permissions)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "server_ca_cert" {
  description = "Server CA certificate metadata for direct TLS verification when connecting over private IP without the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.primary.server_ca_cert
  sensitive   = true
}

output "vpc_network" {
  description = "Resource URI of the custom environment VPC network ('apps-<environment>') attached via Private Services Access."
  value       = local.vpc_network_id
}

output "effective_database_flags" {
  description = "Complete map of PostgreSQL flags active on the primary instance, combining mandatory IAM/pgAudit security flags, DBA observability defaults, and instance-specific overrides."
  value       = local.primary_database_flags
}

output "databases" {
  description = "Map of managed logical PostgreSQL databases keyed by database name."
  value = {
    for name, db in google_sql_database.database :
    name => {
      name      = db.name
      charset   = db.charset
      collation = db.collation
      self_link = db.self_link
    }
  }
}

output "iam_database_principals" {
  description = "Google identities configured for IAM database authentication, including the exact PostgreSQL login username mapped for each workload service account."
  value = {
    users = sort(tolist(keys(google_sql_user.iam_user)))
    service_accounts = {
      for sa_email, sql_user in google_sql_user.iam_service_account :
      sa_email => sql_user.name
    }
    groups = sort(tolist(keys(google_sql_user.iam_group)))
  }
}

output "read_replicas" {
  description = "Connection and identity details for each managed read replica, keyed by replica identifier."
  value = {
    for key, replica in google_sql_database_instance.read_replica :
    key => {
      instance_name         = replica.name
      connection_name       = replica.connection_name
      private_ip_address    = replica.private_ip_address
      dns_name              = replica.dns_name
      region                = replica.region
      self_link             = replica.self_link
      service_account_email = replica.service_account_email_address
    }
  }
}
