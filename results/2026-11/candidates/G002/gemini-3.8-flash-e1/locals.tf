locals {
  # Resolved Google Cloud project ID
  project_id = coalesce(var.project, data.google_client_config.current.project)

  # Normalized environment name (dev, staging, or prod)
  clean_environment = replace(var.environment, "apps-", "")

  # VPC network self-link for Private Services Access
  raw_network  = coalesce(var.network, "apps-${local.clean_environment}")
  network_link = startswith(local.raw_network, "projects/") ? local.raw_network : "projects/${local.project_id}/global/networks/${local.raw_network}"

  # High availability failover: REGIONAL for prod, ZONAL for others by default
  availability_type = coalesce(var.availability_type, local.clean_environment == "prod" ? "REGIONAL" : "ZONAL")

  # Deletion protection: protected by default in prod and staging; disabled in dev
  deletion_protection = coalesce(var.deletion_protection, contains(["prod", "staging"], local.clean_environment))

  # Baseline organizational database flags:
  # - IAM authentication enabled for Google identities
  # - pgAudit and query/connection logging for security team auditing
  # - PostgreSQL operational best practices
  baseline_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "all"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_checkpoints"             = "on"
    "log_min_messages"            = "warning"
    "log_temp_files"              = "0"
  }

  # Effective flags: DBAs can customize, add, or override flags
  effective_database_flags = merge(local.baseline_database_flags, var.database_flags)

  # Standard tags / labels merged with user labels
  effective_labels = merge(
    {
      "environment" = local.clean_environment
      "managed_by"  = "opentofu"
      "team"        = "dba"
    },
    var.labels
  )

  # Normalized database objects
  normalized_databases = {
    for item in var.databases :
    (can(item.name) ? item.name : tostring(item)) => {
      name      = can(item.name) ? item.name : tostring(item)
      charset   = can(item.charset) && item.charset != null ? item.charset : "UTF8"
      collation = can(item.collation) && item.collation != null ? item.collation : "en_US.UTF8"
    }
  }

  # Normalized IAM service account names:
  # Cloud SQL PostgreSQL expects service account usernames without the '.gserviceaccount.com' suffix
  normalized_iam_service_accounts = toset([
    for sa in var.iam_service_accounts : trimsuffix(sa, ".gserviceaccount.com")
  ])
}
