locals {
  # ---------------------------------------------------------------------------
  # Naming: every instance is "<environment>-<name>" so nobody has to invent a
  # convention per instance and names never collide across environments.
  # ---------------------------------------------------------------------------
  instance_name = "${var.environment}-${var.name}"

  # ---------------------------------------------------------------------------
  # Networking: one PSA-ready VPC per environment, owned by the network team.
  # The instance always attaches to apps-<environment> unless an explicit
  # override self link is supplied.
  # ---------------------------------------------------------------------------
  network_project   = var.project != null ? var.project : data.google_client_config.current.project
  network_name      = "apps-${var.environment}"
  network_self_link = var.network != null ? var.network : "https://www.googleapis.com/compute/v1/projects/${local.network_project}/global/networks/${local.network_name}"

  # ---------------------------------------------------------------------------
  # Access: IAM database authentication is mandatory everywhere — every person
  # and workload connects as a Google identity the security team can audit.
  # DBA-supplied flags are preserved, but iam_authentication cannot be turned off.
  # ---------------------------------------------------------------------------
  database_flags = merge(var.database_flags, {
    "cloudsql.iam_authentication" = "on"
  })

  # ---------------------------------------------------------------------------
  # Tagging: standard labels on every instance, plus any extras the DBA wants.
  # ---------------------------------------------------------------------------
  labels = merge({
    environment = var.environment
    managed_by  = "opentofu"
  }, var.labels)

  backup_start_time = format("%02d:00:00", var.backup_start_hour)
}
