output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "\"project:region:name\" connection name, used by Cloud SQL connectors and the Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "instance_self_link" {
  description = "URI of the instance."
  value       = google_sql_database_instance.this.self_link
}

output "private_ip_address" {
  description = "Private (VPC) IP address of the instance — the only address it has."
  value       = google_sql_database_instance.this.private_ip_address
}

output "instance_service_account_email" {
  description = "Service account of the Cloud SQL instance itself, e.g. for granting it KMS or storage access."
  value       = google_sql_database_instance.this.service_account_email_address
}

output "database_names" {
  description = "Application databases created by the module."
  value       = sort(keys(google_sql_database.this))
}

output "iam_logins" {
  description = "IAM database logins created by the module (service accounts shown without the .gserviceaccount.com suffix, as Cloud SQL requires)."
  value = sort(concat(
    [for u in google_sql_user.iam_users : u.name],
    [for u in google_sql_user.iam_service_accounts : u.name],
  ))
}
