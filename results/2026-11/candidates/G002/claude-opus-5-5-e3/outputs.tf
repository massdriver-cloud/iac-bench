output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address on the apps-<environment> network."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Instance self link."
  value       = google_sql_database_instance.this.self_link
}

output "service_account_email" {
  description = "Cloud SQL service account of the instance (for granting e.g. GCS import/export access)."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "databases" {
  description = "Names of databases created."
  value       = [for d in google_sql_database.this : d.name]
}

output "iam_database_usernames" {
  description = "PostgreSQL role names for the IAM identities (service accounts have the .gserviceaccount.com suffix stripped)."
  value = merge(
    { for u, r in google_sql_user.iam_user : u => r.name },
    { for s, r in google_sql_user.iam_service_account : s => r.name },
    { for g, r in google_sql_user.iam_group : g => r.name },
  )
}
