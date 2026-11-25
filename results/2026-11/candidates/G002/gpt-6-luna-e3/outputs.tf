output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance), usable by Cloud SQL connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Assigned private IPv4 address for connections from the attached VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_name" {
  description = "Name of the initial PostgreSQL database."
  value       = google_sql_database.initial.name
}

output "iam_user_names" {
  description = "Cloud SQL IAM database usernames provisioned by this module."
  value       = { for key, user in google_sql_user.iam : key => user.name }
}
