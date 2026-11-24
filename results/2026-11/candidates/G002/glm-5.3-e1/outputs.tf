output "instance_name" {
  description = "Name of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.name
}

output "instance_self_link" {
  description = "Self link of the primary Cloud SQL instance."
  value       = google_sql_database_instance.primary.self_link
}

output "instance_connection_name" {
  description = "Connection name of the primary instance, as needed by the Cloud SQL connectors / Auth Proxy (projects/<project>/locations/<region>/instances/<name>)."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the primary instance. Reachable from the environment VPC; point your application's host at this."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "instance_service_account_email" {
  description = "Service account the instance runs as. Grant it roles/cloudkms.cryptoKeyEncrypterDecrypter on the key when kms_key_name is set."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "read_replica_names" {
  description = "Names of the read replicas."
  value       = [for name, replica in google_sql_database_instance.read_replicas : name]
}

output "read_replica_connection_names" {
  description = "Connection names of the read replicas, keyed by replica name."
  value       = { for name, replica in google_sql_database_instance.read_replicas : name => replica.connection_name }
}

output "read_replica_private_ip_addresses" {
  description = "Private IP addresses of the read replicas, keyed by replica name."
  value       = { for name, replica in google_sql_database_instance.read_replicas : name => replica.private_ip_address }
}

output "database_names" {
  description = "Names of the databases this module manages on the instance."
  value       = [for name, database in google_sql_database.databases : name]
}

output "iam_principals" {
  description = "Every Google identity granted database access, as email -> principal type. This is the access list the security team audits."
  value       = local.iam_principals
}
