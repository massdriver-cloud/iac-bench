output "instance_name" {
  description = "Cloud SQL instance ID."
  value       = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Connection name for Cloud SQL Auth Proxy or language connectors. Configure the client to use private IP."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Internal address for clients connecting directly from the VPC."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_names" {
  description = "Names of the application databases managed by this root module."
  value       = sort(keys(google_sql_database.application))
}

output "iam_database_logins" {
  description = "PostgreSQL login names, keyed by the full Google identity email."
  value = merge(
    { for email, user in google_sql_user.human : email => user.name },
    { for email, user in google_sql_user.workload : email => user.name }
  )
}
