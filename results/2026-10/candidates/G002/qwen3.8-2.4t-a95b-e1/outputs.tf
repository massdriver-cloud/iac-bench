output "name" {
  description = "Instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:name) for psql / Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address, reachable only from the environment's VPC network."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Self link of the instance."
  value       = google_sql_database_instance.this.self_link
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = local.network_self_link
}

output "instance_service_account_email" {
  description = "The instance's service account email, for integrations that need it."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "iam_users" {
  description = "Google identities provisioned as IAM database users."
  value       = [for u in google_sql_user.iam_users : u.name]
}

output "databases" {
  description = "Databases created on the instance."
  value       = [for d in google_sql_database.databases : d.name]
}
