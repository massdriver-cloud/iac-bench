###############################################################################
# Outputs
###############################################################################

output "instance_name" {
  description = "Name of the primary instance."
  value       = google_sql_database_instance.primary.name
}

output "instance_id" {
  description = "ID of the primary instance."
  value       = google_sql_database_instance.primary.id
}

output "self_link" {
  description = "Self link of the primary instance."
  value       = google_sql_database_instance.primary.self_link
}

output "connection_name" {
  description = "Connection name of the primary instance (project:region:instance), as needed by the Cloud SQL Auth Proxy, the language connectors and the Cloud SQL clients."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the primary instance, reachable from GKE and Compute Engine workloads in the same network."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "service_account_email_address" {
  description = "Service account the instance runs as, useful when granting the instance access to other resources, for example a Cloud Storage bucket for import and export."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "databases" {
  description = "Databases created on the instance, name => self link."
  value       = { for name, db in google_sql_database.databases : name => db.self_link }
}

output "iam_login_names" {
  description = "Principal email => PostgreSQL login name to use with IAM database authentication. Service accounts log in as their email without the .gserviceaccount.com suffix."
  value       = { for email, p in local.iam_principals : email => p.login_name }
}

output "replicas" {
  description = "Read replicas, key => { name, connection_name, private_ip_address }."
  value = {
    for key, replica in google_sql_database_instance.replicas :
    key => {
      name            = replica.name
      connection_name = replica.connection_name
      private_ip      = replica.private_ip_address
    }
  }
}
