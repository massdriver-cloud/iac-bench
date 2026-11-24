output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_connection_name" {
  description = "Cloud SQL connection name (project:region:instance), used by Cloud SQL connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "private_ip_address" {
  description = "Private IP address on the supplied VPC. There is no public IP address."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_version" {
  description = "PostgreSQL major version configured on the instance."
  value       = google_sql_database_instance.this.database_version
}

output "databases" {
  description = "Names of additional databases managed by this module."
  value       = sort(keys(google_sql_database.additional))
}

output "iam_database_users" {
  description = "IAM database principals registered on the instance, keyed by the supplied email address."
  value = {
    for email, user in google_sql_user.iam : email => {
      name = user.name
      type = user.type
    }
  }
}

output "connection_security" {
  description = "Connection security settings enforced by the module."
  value = {
    private_ip_only        = true
    ssl_mode               = "ENCRYPTED_ONLY"
    iam_authentication     = true
    password_users_created = false
  }
}
