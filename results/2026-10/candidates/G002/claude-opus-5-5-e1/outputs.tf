output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance on the apps-<environment> VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = local.network_self_link
}

output "databases" {
  description = "Databases created on the instance."
  value       = [for d in google_sql_database.this : d.name]
}

output "iam_database_usernames" {
  description = "PostgreSQL usernames for the IAM principals, as used in connection strings."
  value = concat(
    [for u in google_sql_user.iam_user : u.name],
    [for s in google_sql_user.iam_service_account : s.name],
    [for g in google_sql_user.iam_group : g.name],
  )
}
