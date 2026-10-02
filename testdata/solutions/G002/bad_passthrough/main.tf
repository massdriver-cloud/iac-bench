terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

variable "name" { type = string }
variable "database_version" { type = string }
variable "root_password" { type = string }
variable "tier" { type = string }
variable "edition" {
  type    = string
  default = "ENTERPRISE"
}
variable "availability_type" {
  type    = string
  default = "ZONAL"
}
variable "disk_type" {
  type    = string
  default = "PD_SSD"
}
variable "disk_size" {
  type    = number
  default = 10
}
variable "disk_autoresize" {
  type    = bool
  default = true
}
variable "disk_autoresize_limit" {
  type    = number
  default = 0
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "deletion_protection_enabled" {
  type    = bool
  default = false
}
variable "ipv4_enabled" {
  type    = bool
  default = true
}
variable "private_network" {
  type    = string
  default = null
}
variable "ssl_mode" {
  type    = string
  default = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
}
variable "authorized_networks" {
  type    = map(string)
  default = {}
}
variable "backup_enabled" {
  type    = bool
  default = false
}
variable "point_in_time_recovery_enabled" {
  type    = bool
  default = false
}
variable "backup_start_time" {
  type    = string
  default = null
}
variable "retained_backups" {
  type    = number
  default = 7
}
variable "transaction_log_retention_days" {
  type    = number
  default = 7
}
variable "maintenance_day" {
  type    = number
  default = null
}
variable "maintenance_hour" {
  type    = number
  default = null
}
variable "maintenance_update_track" {
  type    = string
  default = "stable"
}
variable "query_insights_enabled" {
  type    = bool
  default = false
}
variable "database_flags" {
  type    = map(string)
  default = {}
}
variable "user_labels" {
  type    = map(string)
  default = {}
}
variable "activation_policy" {
  type    = string
  default = "ALWAYS"
}

resource "google_sql_database_instance" "this" {
  name                = var.name
  database_version    = var.database_version
  root_password       = var.root_password
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = var.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size
    disk_autoresize             = var.disk_autoresize
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = var.deletion_protection_enabled
    activation_policy           = var.activation_policy
    user_labels                 = var.user_labels

    ip_configuration {
      ipv4_enabled    = var.ipv4_enabled
      private_network = var.private_network
      ssl_mode        = var.ssl_mode

      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.key
          value = authorized_networks.value
        }
      }
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      start_time                     = var.backup_start_time
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
      }
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = var.maintenance_update_track
    }

    insights_config {
      query_insights_enabled = var.query_insights_enabled
    }

    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

output "connection_name" {
  value = google_sql_database_instance.this.connection_name
}
