output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "connection_name" {
  description = "project:region:name connection string, used by the Cloud SQL Auth Proxy and the language connectors from GKE and Compute Engine."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance on the environment VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "service_account_email_address" {
  description = "Service account Cloud SQL created for this instance."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "database_names" {
  description = "Names of the databases created on the instance by this module."
  value       = keys(google_sql_database.this)
}

output "iam_users" {
  description = "Map of logical name to the database login created for each Google identity."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}
