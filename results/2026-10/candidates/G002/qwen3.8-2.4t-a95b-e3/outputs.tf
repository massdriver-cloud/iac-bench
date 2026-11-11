output "instance_name" {
  description = "Cloud SQL instance name (already includes the environment prefix)."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "project:region:instance connection name — pass to cloud-sql-proxy or the GKE sidecar."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address reachable from the environment VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = local.network_self_link
}

output "databases" {
  description = "Application databases created on the instance."
  value       = [for db in google_sql_database.this : db.name]
}
