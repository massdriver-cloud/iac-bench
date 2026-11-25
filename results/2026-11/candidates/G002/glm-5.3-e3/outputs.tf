# =========================================================================
# Outputs
# =========================================================================

output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "connection_name" {
  description = "Connection name (<project>:<region>:<instance>) for the Cloud SQL Auth Proxy and language connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IPv4 address of the instance. Reachable only from var.network and networks peered with it; there is no public IP."
  value       = google_sql_database_instance.this.private_ip_address
}

output "databases" {
  description = "Databases the module created on the instance."
  value       = sort([for db in google_sql_database.this : db.name])
}

output "iam_users" {
  description = "Google identities registered on the instance, email to Cloud SQL user type."
  value       = { for email, user in var.iam_users : email => user.type }
}
