output "instance_name" {
  description = "The name of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.postgresql.name
}

output "instance_id" {
  description = "The resource identifier of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.postgresql.id
}

output "self_link" {
  description = "The URI of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.postgresql.self_link
}

output "connection_name" {
  description = "The connection name of the instance to be used in Cloud SQL Auth Proxy or connection strings (project:region:instance)."
  value       = google_sql_database_instance.postgresql.connection_name
}

output "private_ip_address" {
  description = "The private IPv4 address assigned to the Cloud SQL instance on the environment's VPC network."
  value       = google_sql_database_instance.postgresql.private_ip_address
}

output "dns_name" {
  description = "The DNS name of the Cloud SQL instance."
  value       = google_sql_database_instance.postgresql.dns_name
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.postgresql.service_account_email_address
}

output "server_ca_cert" {
  description = "The CA certificate information used to verify the Cloud SQL server identity."
  value       = google_sql_database_instance.postgresql.server_ca_cert
  sensitive   = true
}

output "vpc_network_id" {
  description = "The ID of the environment VPC network to which the instance is connected via private services access."
  value       = data.google_compute_network.vpc.id
}

output "databases" {
  description = "Map of provisioned database names to their Cloud SQL database resource IDs."
  value       = { for k, db in google_sql_database.databases : k => db.id }
}

output "iam_users" {
  description = "Map of provisioned IAM user keys to their formatted Cloud SQL database usernames."
  value       = { for k, u in google_sql_user.iam_users : k => u.name }
}
