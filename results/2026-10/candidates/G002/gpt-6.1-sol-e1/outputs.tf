output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "project:region:instance identifier for the Cloud SQL Auth Proxy and language connectors. Select private IP and automatic IAM authentication."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private address; direct PostgreSQL connections are blocked by connector enforcement."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_names" {
  description = "Managed database names."
  value       = { for name, database in google_sql_database.this : name => database.name }
}

output "iam_database_usernames" {
  description = "IAM principal to PostgreSQL login name (service account suffix removed)."
  value       = { for member, identity in local.identities : member => identity.name }
}
