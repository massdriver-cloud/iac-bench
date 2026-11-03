output "connection_name" {
  description = "Connection name for the Cloud SQL connectors and Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance."
  value       = google_sql_database_instance.this.private_ip_address
}

output "server_ca_cert" {
  description = "Server CA certificate clients use to verify the instance."
  value       = google_sql_database_instance.this.server_ca_cert[0].cert
  sensitive   = true
}
