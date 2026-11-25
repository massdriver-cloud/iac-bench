output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "Cloud SQL connection name used by the Auth Proxy and language connectors (PROJECT:REGION:INSTANCE)."
  value       = google_sql_database_instance.this.connection_name
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "private_ip_address" {
  description = "Private VPC IP address assigned to the instance. No public IP is allocated."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_version" {
  description = "PostgreSQL major version configured on the instance."
  value       = google_sql_database_instance.this.database_version
}

output "database_names" {
  description = "Names of additional databases managed by the module."
  value       = sort(keys(google_sql_database.this))
}

output "iam_user_names" {
  description = "Cloud SQL IAM database user names managed by the module."
  value       = sort(keys(google_sql_user.iam))
}

output "iam_members" {
  description = "IAM member identifiers corresponding to iam_user_names, useful for access auditing."
  value       = sort([for principal in local.iam_principals : principal.member])
}

output "private_network" {
  description = "Existing VPC self link used for private connectivity."
  value       = var.network_self_link
}
