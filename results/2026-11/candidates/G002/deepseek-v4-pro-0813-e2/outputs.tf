output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.primary.name
}

output "instance_connection_name" {
  description = "Connection name (project:region:instance) used by the Cloud SQL Auth proxy."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the primary instance."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "region" {
  description = "Region of the primary instance."
  value       = google_sql_database_instance.primary.region
}

output "database_names" {
  description = "Names of the databases created."
  value       = keys(google_sql_database.db)
}

output "replica_connection_names" {
  description = "Connection names of any read replicas."
  value       = [for r in google_sql_database_instance.replica : r.connection_name]
}

output "iam_grants_sql" {
  description = "SQL to grant the configured IAM identities access to their databases. Apply as a privileged PostgreSQL user after the instance is created."
  value = join("\n", flatten([
    for db, principals in var.iam_users : [
      for p in principals : "GRANT ALL PRIVILEGES ON DATABASE \"${db}\" TO \"${p}\";"
    ]
  ]))
}