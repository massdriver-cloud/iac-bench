terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

variable "name" {
  type = string
}

resource "google_sql_database_instance" "db" {
  name             = var.name
  database_version = "POSTGRES_16"

  settings {
    tier    = "db-custom-1-3840"
    edition = "ENTERPRISE"
  }
}

output "ip" {
  value = google_sql_database_instance.db.public_ip_address
}
