locals {
  network_project = coalesce(var.network_project_id, var.project_id)

  # The apps network for this environment. The network team owns it and has
  # already configured private services access (servicenetworking peering).
  network_name = "apps-${var.environment}"

  is_prod = var.environment == "prod"

  standard_labels = {
    environment = var.environment
    managed-by  = "opentofu"
    module      = "cloudsql-postgres"
  }

  labels = merge(var.labels, local.standard_labels)

  # ---------------------------------------------------------------------------
  # Locked baseline. Identical on every instance the module creates.
  # DBAs cannot override these through additional_database_flags.
  # ---------------------------------------------------------------------------
  baseline_database_flags = {
    # Authentication: Google identities only (IAM database authentication).
    "cloudsql.iam_authentication" = "on"

    # Connection and session audit trail.
    "log_connections"    = "on"
    "log_disconnections" = "on"

    # Operational logging.
    "log_checkpoints"         = "on"
    "log_lock_waits"          = "on"
    "log_min_error_statement" = "error"
    "log_temp_files"          = "0"

    # Security audit: pgaudit records DDL and role/privilege changes.
    "cloudsql.enable_pgaudit" = "on"
    "pgaudit.log"             = "ddl,role"
  }

  # Extra flags supplied by DBAs. Must not collide with the locked baseline.
  extra_database_flags = [
    for k, v in var.additional_database_flags : { name = k, value = v }
  ]

  database_flags = concat(
    [for k, v in local.baseline_database_flags : { name = k, value = v }],
    local.extra_database_flags,
  )

  locked_flag_collisions = setintersection(
    keys(var.additional_database_flags),
    keys(local.baseline_database_flags),
  )

  # ---------------------------------------------------------------------------
  # Identities
  # ---------------------------------------------------------------------------
  iam_principals = {
    for p in var.iam_principals : p.email => p
  }

  # Cloud SQL IAM role names: users use the full email; service accounts drop
  # the .gserviceaccount.com suffix.
  iam_user_names = {
    for email, p in local.iam_principals : email => (
      p.type == "service_account" ? trimsuffix(email, ".gserviceaccount.com") : email
    )
  }
}
