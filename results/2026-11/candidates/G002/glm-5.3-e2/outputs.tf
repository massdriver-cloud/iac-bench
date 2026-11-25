output "instance_name" {
  description = "Name of the primary instance."
  value       = google_sql_database_instance.primary.name
}

output "instance_connection_name" {
  description = "Connection name to hand to the Cloud SQL connectors or the auth proxy sidecar (GKE / Compute Engine workloads)."
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the primary instance, reachable from the environment's VPC."
  value       = google_sql_database_instance.primary.private_ip_address
}

output "server_ca_certificate" {
  description = "Server CA certificate (PEM) for direct TLS connections such as psql; the connectors fetch it automatically."
  value       = try(google_sql_database_instance.primary.server_ca_cert[0].cert, null)
}

output "service_account_email_address" {
  description = "The instance's Cloud SQL service account — grant it roles/cloudkms.cryptoKeyEncrypterDecrypter on the KMS key before applying with kms_key_name."
  value       = google_sql_database_instance.primary.service_account_email_address
}

output "database_names" {
  description = "Names of the databases the module manages on this instance."
  value       = keys(var.databases)
}

output "read_replica_connection_names" {
  description = "Connection names of the read replicas, keyed by replica name."
  value       = { for k, r in google_sql_database_instance.read_replica : k => r.connection_name }
}

output "read_replica_private_ip_addresses" {
  description = "Private IP addresses of the read replicas, keyed by replica name."
  value       = { for k, r in google_sql_database_instance.read_replica : k => r.private_ip_address }
}
