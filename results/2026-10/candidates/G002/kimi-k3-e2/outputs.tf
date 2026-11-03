output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "project:region:name — used by the Cloud SQL Auth Proxy, language connectors and GKE sidecars."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance inside the VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "API self-link of the instance."
  value       = google_sql_database_instance.this.self_link
}

output "server_ca_cert" {
  description = "Server CA certificate, for clients that verify the server when connecting with ssl_mode ENCRYPTED_ONLY."
  value       = google_sql_database_instance.this.server_ca_cert
  sensitive   = true
}

output "effective_database_flags" {
  description = "Database flags after merging the DBA-provided flags with the module-enforced ones — useful for audits."
  value       = local.database_flags
}

output "databases" {
  description = "Names of the databases created by the module."
  value       = keys(google_sql_database.this)
}

output "iam_users" {
  description = "IAM database users created by the module (keyed like var.iam_users)."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}
