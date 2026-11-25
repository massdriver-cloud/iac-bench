output "project_id" {
  description = "GCP project ID where the Cloud SQL instance is deployed."
  value       = data.google_project.current.project_id
}

output "instance_name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "instance_connection_name" {
  description = "Connection name (<project>:<region>:<instance>) for Cloud SQL Auth Proxy and Language Connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "instance_self_link" {
  description = "Self link of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "private_ip_address" {
  description = "Private VPC IP address of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "vpc_network" {
  description = "VPC network self link attached to the Cloud SQL instance."
  value       = data.google_compute_network.vpc.id
}

output "database_version" {
  description = "PostgreSQL version running on the instance."
  value       = google_sql_database_instance.primary.database_version
}

output "service_account_email" {
  description = "GCP service account email managed by Cloud SQL for this instance (e.g. for GCS export/import permissions)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "databases" {
  description = "Names of databases created on the primary instance."
  value       = sort(keys(google_sql_database.databases))
}

output "iam_users" {
  description = "IAM database users configured on the instance."
  value = {
    for k, u in google_sql_user.iam_users : k => {
      name = u.name
      type = u.type
    }
  }
}

output "read_replicas" {
  description = "Details of read replica instances keyed by replica suffix."
  value = {
    for k, r in google_sql_database_instance.read_replicas : k => {
      instance_name            = r.name
      instance_connection_name = r.connection_name
      private_ip_address       = r.private_ip_address
      region                   = r.region
    }
  }
}
