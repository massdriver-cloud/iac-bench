output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy and connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance on the environment VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "service_account_email" {
  description = "Service account the instance runs as (grant it KMS / bucket access when needed)."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "server_ca_cert" {
  description = "PEM-encoded server CA certificate, for clients that verify the server."
  value       = try(google_sql_database_instance.this.server_ca_cert[0].cert, null)
}

output "database_version" {
  description = "PostgreSQL version running on the instance."
  value       = google_sql_database_instance.this.database_version
}

output "databases" {
  description = "Names of the databases managed by this module."
  value       = sort(keys(google_sql_database.this))
}

output "iam_database_users" {
  description = "Map of Google identity => database username to use when logging in with IAM authentication."
  value = merge(
    { for email, u in google_sql_user.iam_users : email => u.name },
    { for email, g in google_sql_user.iam_groups : email => g.name },
  )
}

output "break_glass_admin_user" {
  description = "Name of the break-glass admin user, if one was created."
  value       = var.break_glass_admin
}

output "break_glass_admin_secret" {
  description = "Secret Manager secret holding the break-glass admin password, if one was created."
  value       = try(google_secret_manager_secret.break_glass_admin[0].id, null)
}
