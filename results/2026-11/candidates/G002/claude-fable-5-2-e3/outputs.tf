output "instance_name" {
  description = "Name of the primary instance."
  value       = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy and language connectors."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the primary on the apps-<environment> network."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "dns_name" {
  description = "Instance-level DNS name of the primary, if Cloud SQL assigned one."
  value       = google_sql_database_instance.primary.dns_name
}

output "self_link" {
  description = "Self link of the primary instance."
  value       = google_sql_database_instance.primary.self_link
}

output "database_version" {
  description = "PostgreSQL major version of the instance."
  value       = google_sql_database_instance.primary.database_version
}

output "availability_type" {
  description = "REGIONAL (high availability) or ZONAL."
  value       = google_sql_database_instance.primary.settings[0].availability_type
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = local.network
}

output "service_account_email_address" {
  description = "The instance's service account, for granting access to Cloud Storage buckets used for import/export."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "databases" {
  description = "Names of the databases managed by this module."
  value       = sort([for d in google_sql_database.this : d.name])
}

output "iam_database_users" {
  description = "IAM principal => PostgreSQL role name and type. Use the role name in GRANT statements and as the login user."
  value = {
    for member, u in google_sql_user.iam : member => {
      name = u.name
      type = u.type
    }
  }
}

output "database_flags" {
  description = "The effective PostgreSQL flags on the instance: module defaults, DBA-supplied flags and enforced flags combined."
  value       = local.database_flags
}

output "read_replicas" {
  description = "Read replicas, keyed as in var.read_replicas."
  value = {
    for k, r in google_sql_database_instance.replica : k => {
      name               = r.name
      region             = r.region
      connection_name    = r.connection_name
      private_ip_address = r.private_ip_address
    }
  }
}
