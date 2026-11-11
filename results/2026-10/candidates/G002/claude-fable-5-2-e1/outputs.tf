output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy and language connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance on the environment's VPC network."
  value       = google_sql_database_instance.this.private_ip_address
}

output "dns_name" {
  description = "Instance DNS name, usable instead of the IP address for direct TLS connections."
  value       = google_sql_database_instance.this.dns_name
}

output "self_link" {
  description = "URI of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "database_version" {
  description = "PostgreSQL version the instance runs."
  value       = google_sql_database_instance.this.database_version
}

output "availability_type" {
  description = "REGIONAL (highly available) or ZONAL."
  value       = google_sql_database_instance.this.settings[0].availability_type
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = local.network
}

output "databases" {
  description = "Names of the databases managed by this module."
  value       = sort([for db in google_sql_database.this : db.name])
}

output "iam_database_users" {
  description = "Map of each granted Google identity to the PostgreSQL user name it logs in as."
  value       = { for email, user in google_sql_user.iam : email => user.name }
}

output "database_flags" {
  description = "Effective PostgreSQL flags: enforced flags, module defaults and DBA overrides combined."
  value       = local.database_flags
}
