output "instance_name" {
  description = "Cloud SQL primary instance name."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Connection name ('project:region:instance') for Cloud SQL Auth Proxy and Cloud SQL Language Connectors."
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

output "instance_service_account_email" {
  description = "Google-managed service account email associated with the primary Cloud SQL instance (for KMS or Cloud Storage grants)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "server_ca_cert" {
  description = "Server CA certificate metadata and PEM for verifying direct TLS connections to the primary instance."
  value       = google_sql_database_instance.primary.server_ca_cert
  sensitive   = true
}

output "network" {
  description = "Resolved custom VPC network to which the instance is privately attached."
  value = {
    name      = data.google_compute_network.vpc.name
    id        = data.google_compute_network.vpc.id
    self_link = data.google_compute_network.vpc.self_link
  }
}

output "effective_database_flags" {
  description = "Complete resolved map of PostgreSQL database flags applied to the primary instance (defaults + DBA flags + enforced security/audit flags)."
  value       = local.effective_database_flags
}

output "databases" {
  description = "Names of logical PostgreSQL databases managed on the primary instance."
  value       = [for name in sort(keys(google_sql_database.database)) : google_sql_database.database[name].name]
}

output "iam_database_roles" {
  description = "PostgreSQL role names created for each Google identity (note that service account roles omit '.gserviceaccount.com' in PostgreSQL)."
  value = {
    users            = { for email, u in google_sql_user.iam_user : email => u.name }
    service_accounts = { for sa, u in google_sql_user.iam_service_account : sa => u.name }
    groups           = { for group, u in google_sql_user.iam_group : group => u.name }
  }
}

output "read_replicas" {
  description = "Connection details for each configured read replica, keyed by replica identifier."
  value = {
    for key, replica in google_sql_database_instance.read_replica :
    key => {
      instance_name      = replica.name
      connection_name    = replica.connection_name
      private_ip_address = replica.private_ip_address
      dns_name           = replica.dns_name
      region             = replica.region
      self_link          = replica.self_link
    }
  }
}
