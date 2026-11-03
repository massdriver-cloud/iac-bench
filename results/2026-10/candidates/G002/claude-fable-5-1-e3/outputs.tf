output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "instance_id" {
  description = "Fully qualified instance id (projects/.../instances/...)."
  value       = google_sql_database_instance.this.id
}

output "connection_name" {
  description = "Connection name for the Cloud SQL Auth Proxy / connectors (project:region:instance)."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP of the instance on the apps-<environment> VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Instance self link."
  value       = google_sql_database_instance.this.self_link
}

output "availability_type" {
  description = "Effective availability type."
  value       = local.availability_type
}

output "network" {
  description = "VPC the instance is attached to."
  value       = local.network_id
}

output "databases" {
  description = "Names of the databases managed on the instance."
  value       = sort(keys(google_sql_database.this))
}

output "iam_users" {
  description = "Map of Google identity e-mail => Cloud SQL IAM user name."
  value       = { for email, u in local.iam_users : email => u.sql_user_name }
}

output "database_flags" {
  description = "Effective database flags (DBA-supplied merged with module-enforced)."
  value       = local.database_flags
}
