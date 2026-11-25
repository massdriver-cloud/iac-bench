output "instance_name" {
  description = "Name of the primary Cloud SQL for PostgreSQL instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance) for Cloud SQL Auth Proxy and language connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IPv4 address of the primary Cloud SQL instance on the apps-<environment> VPC network."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "dns_name" {
  description = "Instance-level DNS name of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.dns_name
}

output "self_link" {
  description = "Self-link URI of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "service_account_email_address" {
  description = "Google-managed service account email associated with the primary Cloud SQL instance (used for GCS import/export and KMS)."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "network" {
  description = "Self-link of the custom VPC network attached to the instance via Private Services Access."
  value       = local.network_self_link
}

output "databases" {
  description = "List of logical PostgreSQL database names managed on the instance."
  value       = sort([for db in google_sql_database.database : db.name])
}

output "iam_database_users" {
  description = "Map of Google identities to their provisioned PostgreSQL database username and IAM user type."
  value = merge(
    {
      for email, u in google_sql_user.iam_user :
      email => {
        postgres_username = u.name
        type              = u.type
      }
    },
    {
      for sa, u in google_sql_user.iam_service_account :
      sa => {
        postgres_username = u.name
        type              = u.type
      }
    },
    {
      for grp, u in google_sql_user.iam_group :
      grp => {
        postgres_username = u.name
        type              = u.type
      }
    },
  )
}

output "effective_database_flags" {
  description = "Resolved map of all PostgreSQL flags applied to the primary instance (including enforced IAM and audit flags)."
  value       = local.primary_database_flags
}

output "read_replicas" {
  description = "Connection details for each configured read replica, keyed by replica name suffix."
  value = {
    for k, r in google_sql_database_instance.read_replica :
    k => {
      instance_name      = r.name
      connection_name    = r.connection_name
      private_ip_address = r.private_ip_address
      dns_name           = r.dns_name
      region             = r.region
      self_link          = r.self_link
    }
  }
}
