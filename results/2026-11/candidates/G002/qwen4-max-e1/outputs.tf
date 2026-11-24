output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance on the apps-<environment> network. There is no public IP."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "service_account_email" {
  description = "Service account of the instance itself (useful for CMEK / storage permissions)."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "database_names" {
  description = "Application databases created on the instance."
  value       = [for db in google_sql_database.this : db.name]
}

output "iam_database_user_names" {
  description = "Google-identity database users registered on the instance."
  value       = [for u in google_sql_user.iam : u.name]
}
