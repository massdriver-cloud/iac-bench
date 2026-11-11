###############################################################################
# Outputs.
#
# Deliberately absent: the postgres password. It lives in Secret Manager, not
# in CI logs - fetch it with
#   gcloud secrets versions access latest --secret=cloudsql-<name>-postgres-password
###############################################################################

output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "Connection name for the Cloud SQL connectors / Auth Proxy (what GKE and Compute Engine workloads use to reach the instance)."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP of the instance, reachable only from the VPC passed in `network` over private services access."
  value       = google_sql_database_instance.this.private_ip_address
}

output "instance_self_link" {
  description = "Self link of the instance."
  value       = google_sql_database_instance.this.self_link
}

output "databases" {
  description = "Names of the databases managed on this instance."
  value       = sort(keys(google_sql_database.this))
}

output "iam_users" {
  description = "IAM database logins created on this instance, identity -> Cloud SQL user type."
  value       = { for name, u in local.iam_users : name => u.type }
}

output "postgres_password_secret" {
  description = "Resource id of the Secret Manager secret holding the break-glass postgres password (null when not managed)."
  value       = var.manage_postgres_password ? google_secret_manager_secret.postgres_password[0].id : null
}

output "server_ca_certificate" {
  description = "Server CA certificate (PEM) that clients use to verify TLS connections (sslmode=verify-full). The provider marks this attribute sensitive; the certificate itself is public."
  value       = try(google_sql_database_instance.this.server_ca_cert[0].cert, null)
  sensitive   = true
}
