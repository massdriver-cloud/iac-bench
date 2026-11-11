locals {
  availability_type = coalesce(
    var.availability_type,
    var.environment == "prod" ? "REGIONAL" : "ZONAL"
  )

  standard_labels = {
    component   = "postgresql"
    environment = var.environment
    managed-by  = "opentofu"
  }

  # These low-noise flags make connection and operational events visible in
  # Cloud Logging. DBAs may override them, but IAM authentication is mandatory.
  default_database_flags = {
    log_checkpoints    = "on"
    log_connections    = "on"
    log_disconnections = "on"
    log_lock_waits     = "on"
  }

  database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    { "cloudsql.iam_authentication" = "on" }
  )
}
