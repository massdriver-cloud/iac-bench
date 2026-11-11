###############################################################################
# Outputs
###############################################################################

output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.instance.name
}

output "instance_connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL language connectors and the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.instance.connection_name
}

output "private_ip_address" {
  description = "The instance's private IP address in apps-<environment>. It has no other address."
  value       = google_sql_database_instance.instance.private_ip_address
}

output "server_ca_certificate" {
  description = "Server CA certificate (PEM) for clients that connect directly over private IP with sslmode=verify-full. Sensitive only because the provider marks the whole CA block sensitive."
  value       = try(google_sql_database_instance.instance.server_ca_cert[0].cert, null)
  sensitive   = true
}

output "self_link" {
  description = "Self link of the instance."
  value       = google_sql_database_instance.instance.self_link
}

output "database_version" {
  description = "Cloud SQL database version string, e.g. POSTGRES_16."
  value       = local.database_version
}

output "databases" {
  description = "Databases created on the instance."
  value       = [for _, database in google_sql_database.database : database.name]
}

output "iam_principals" {
  description = "Google identities that can log in to this instance, for the security team's access audits."
  value = {
    users            = [for _, user in google_sql_user.iam_user : user.name]
    service_accounts = [for _, user in google_sql_user.iam_service_account : user.name]
  }
}
