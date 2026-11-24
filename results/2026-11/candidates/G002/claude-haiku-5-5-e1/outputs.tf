output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_self_link" {
  description = "Self link of the Cloud SQL instance."
  value       = google_sql_database_instance.this.self_link
}

output "connection_name" {
  description = "Connection name (project:region:instance) used by the Cloud SQL Auth Proxy and connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address applications connect to from the apps-<environment> VPC."
  value = one([
    for ip in google_sql_database_instance.this.ip_address : ip.ip_address
    if ip.type == "PRIVATE"
  ])
}

output "network" {
  description = "VPC network the instance is attached to."
  value       = data.google_compute_network.apps.name
}

output "databases" {
  description = "Databases created on the instance."
  value       = sort(keys(google_sql_database.this))
}

output "iam_database_users" {
  description = "IAM identities granted database login."
  value = sort(concat(
    [for u in google_sql_user.iam_user : u.name],
    [for s in google_sql_user.iam_service_account : s.name],
  ))
}
