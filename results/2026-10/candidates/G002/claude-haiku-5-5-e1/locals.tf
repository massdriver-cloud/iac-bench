locals {
  # Network the instance attaches to. Created and owned by the network team.
  network_name = "apps-${var.environment}"

  # Flags the module always sets. They are merged last so DBAs cannot
  # override them through var.database_flags.
  #   cloudsql.iam_authentication  - allow IAM identities to log in; no password users
  #   cloudsql.enable_pgaudit      - audit trail for the security team
  #   log_connections / disconnections - who connected, from where, and when
  required_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  # Defaults that DBAs may override.
  default_database_flags = {
    "pgaudit.log"     = "ddl,role"
    "log_lock_waits"  = "on"
    "log_checkpoints" = "on"
    "log_temp_files"  = "0"
  }

  effective_database_flags = merge(local.default_database_flags, var.database_flags, local.required_database_flags)

  common_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  # Cloud SQL IAM service account users are named without the domain suffix.
  iam_service_account_users = {
    for sa in var.iam_service_accounts :
    trimsuffix(sa, ".gserviceaccount.com") => sa
  }
}
