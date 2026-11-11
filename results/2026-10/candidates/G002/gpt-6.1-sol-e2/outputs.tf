output "instance_name" {
  description = "Managed Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Connection name for the Cloud SQL Auth Proxy or language connectors; configure private IP and automatic IAM authentication."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private address; direct connections are blocked by connector enforcement."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_names" {
  description = "Managed application databases."
  value       = { for name, database in google_sql_database.application : name => database.name }
}

output "iam_database_usernames" {
  description = "Identity emails mapped to PostgreSQL login names for connector configuration and DBA SQL grants."
  value       = { for email, user in google_sql_user.iam : email => user.name }
}
