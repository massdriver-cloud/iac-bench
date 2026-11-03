output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "Connection name (project:region:instance) used by the Cloud SQL Auth Proxy and connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance on the apps-<environment> network."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Self link of the instance."
  value       = google_sql_database_instance.this.self_link
}

output "service_account_email_address" {
  description = "Service account Cloud SQL uses for the instance. Grant it access to any KMS keys or GCS export buckets you add."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "network" {
  description = "The apps-<environment> VPC network the instance is attached to."
  value       = data.google_compute_network.apps.id
}

output "databases" {
  description = "Databases created in the instance."
  value       = [for d in google_sql_database.this : d.name]
}

output "iam_database_users" {
  description = "Database role names created for Google identities, keyed by email."
  value       = { for email, u in google_sql_user.iam : email => u.name }
}

output "postgres_break_glass_password" {
  description = "Password for the built-in postgres superuser. Break-glass only; retrieve with tofu output -raw postgres_break_glass_password."
  value       = random_password.postgres.result
  sensitive   = true
}
