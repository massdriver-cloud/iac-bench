output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "project:region:instance for the Cloud SQL Auth Proxy or language connectors. Select private IP and automatic IAM authentication."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private endpoint; connectors must have VPC reachability. Direct PostgreSQL connections are intentionally blocked."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_names" {
  description = "Managed application database names."
  value       = { for key, database in google_sql_database.this : key => database.name }
}

output "iam_database_usernames" {
  description = "Identity email to PostgreSQL username (service-account suffix removed)."
  value       = { for email, user in google_sql_user.iam : email => user.name }
}
