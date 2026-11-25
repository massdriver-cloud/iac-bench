output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance inside the apps-<environment> VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "dns_name" {
  description = "DNS name of the instance (empty for Enterprise edition instances)."
  value       = google_sql_database_instance.this.dns_name
}

output "service_account_email_address" {
  description = "Email of the service account Cloud SQL runs the instance as (grant it bucket access for import/export)."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "server_ca_cert" {
  description = "Server CA certificate (PEM) clients can use to verify the instance's TLS certificate."
  value       = try(google_sql_database_instance.this.server_ca_cert[0].cert, null)
  sensitive   = true
}

output "database_names" {
  description = "Names of the databases created on the instance."
  value       = sort(keys(google_sql_database.this))
}

output "iam_users" {
  description = "Map of IAM principal email => PostgreSQL role name created for it."
  value       = { for p, u in google_sql_user.iam : p => u.name }
}

output "network_self_link" {
  description = "VPC network the instance is attached to."
  value       = local.network_self_link
}
