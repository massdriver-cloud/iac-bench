output "instance_name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance) for use with Cloud SQL Auth Proxy and Language Connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private VPC IPv4 address of the primary instance."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "self_link" {
  description = "Self-link URI of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "service_account_email_address" {
  description = "GCP-managed service account email of the primary Cloud SQL instance (needed when granting CMEK KMS permissions)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "vpc_network" {
  description = "VPC network self-link to which the instance is privately attached."
  value       = data.google_compute_network.vpc.self_link
}

output "databases" {
  description = "Created PostgreSQL databases keyed by database name."
  value = {
    for k, db in google_sql_database.databases : k => {
      name      = db.name
      charset   = db.charset
      collation = db.collation
      self_link = db.self_link
    }
  }
}

output "read_replicas" {
  description = "Read replica details keyed by replica suffix."
  value = {
    for k, replica in google_sql_database_instance.read_replicas : k => {
      instance_name      = replica.name
      connection_name    = replica.connection_name
      private_ip_address = replica.private_ip_address
      region             = replica.region
      self_link          = replica.self_link
    }
  }
}

output "iam_sql_users" {
  description = "PostgreSQL role names created for IAM principals (for granting database/schema privileges)."
  value = {
    users            = [for u in google_sql_user.iam_users : u.name]
    service_accounts = [for sa in google_sql_user.iam_service_accounts : sa.name]
    groups           = [for g in google_sql_user.iam_groups : g.name]
  }
}
