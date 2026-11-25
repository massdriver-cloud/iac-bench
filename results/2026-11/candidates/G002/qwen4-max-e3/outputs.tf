output "instance_name" {
  description = "Cloud SQL instance ID."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP of the instance inside the environment's apps-* VPC. This is the only address; there is no public IP."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_name" {
  description = "Application database created on the instance."
  value       = google_sql_database.app.name
}

output "network" {
  description = "VPC the instance is attached to (private services access)."
  value       = data.google_compute_network.apps.name
}

output "iam_database_users" {
  description = "Google identities registered as database users (as Cloud SQL records them)."
  value       = { for email, u in local.iam_users : email => u.name }
}

output "self_link" {
  description = "Instance self link."
  value       = google_sql_database_instance.this.self_link
}
