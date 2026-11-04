output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance within the environment VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = local.network_id
}

output "service_account_email_address" {
  description = "Cloud SQL service account of the instance (e.g. for granting KMS or GCS access)."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "databases" {
  description = "Logical databases created on the instance."
  value       = sort(keys(google_sql_database.this))
}

output "iam_database_users" {
  description = "IAM database user names created on the instance."
  value       = sort(values(local.iam_db_user_name))
}
