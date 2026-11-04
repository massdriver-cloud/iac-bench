output "instance_name" {
  description = "The name of the Cloud SQL instance."
  value       = google_sql_database_instance.main.name
}

output "instance_self_link" {
  description = "The URI of the Cloud SQL instance."
  value       = google_sql_database_instance.main.self_link
}

output "instance_connection_name" {
  description = "The connection name of the Cloud SQL instance to be used in connection strings or Cloud SQL Proxy."
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip_address" {
  description = "The private IP address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.main.private_ip_address
}

output "public_ip_address" {
  description = "The public IP address assigned to the Cloud SQL instance (if enabled)."
  value       = google_sql_database_instance.main.public_ip_address
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.main.service_account_email_address
}

output "server_ca_cert" {
  description = "The CA certificate information for the Cloud SQL instance."
  value       = google_sql_database_instance.main.server_ca_cert
  sensitive   = true
}

output "databases" {
  description = "Map of created database names."
  value       = { for name, db in google_sql_database.databases : name => db.name }
}

output "builtin_users" {
  description = "List of created built-in SQL database usernames."
  value       = [for u in google_sql_user.builtin_users : u.name]
}

output "iam_users" {
  description = "Map of configured IAM database users and their details."
  value = {
    for email, u in google_sql_user.iam_users : email => {
      db_user_name = u.name
      type         = u.type
    }
  }
}
