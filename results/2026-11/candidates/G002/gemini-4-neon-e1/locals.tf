locals {
  # Environment-specific defaults that keep dev lean and prod resilient
  env_defaults = {
    dev = {
      availability_type      = "ZONAL"
      disk_size_gb           = 20
      backup_retention_count = 7
      update_track           = "canary"
      deletion_protection    = false
      db_deletion_policy     = "DELETE"
      tier_enterprise        = "db-custom-2-8192"
      tier_enterprise_plus   = "db-perf-optimized-N-2"
    }
    staging = {
      availability_type      = "ZONAL"
      disk_size_gb           = 50
      backup_retention_count = 14
      update_track           = "stable"
      deletion_protection    = true
      db_deletion_policy     = "ABANDON"
      tier_enterprise        = "db-custom-2-8192"
      tier_enterprise_plus   = "db-perf-optimized-N-2"
    }
    prod = {
      availability_type      = "REGIONAL"
      disk_size_gb           = 100
      backup_retention_count = 30
      update_track           = "stable"
      deletion_protection    = true
      db_deletion_policy     = "ABANDON"
      tier_enterprise        = "db-custom-4-16384"
      tier_enterprise_plus   = "db-perf-optimized-N-4"
    }
  }

  profile = local.env_defaults[var.environment]

  # Naming matches the organization's <service>-<environment> convention (e.g., apps-prod)
  instance_name = "${var.name}-${var.environment}"
  network_name  = "apps-${var.environment}"

  # Effective primary settings
  region = coalesce(var.region, data.google_client_config.current.region)
  tier = coalesce(
    var.tier,
    var.edition == "ENTERPRISE_PLUS" ? local.profile.tier_enterprise_plus : local.profile.tier_enterprise
  )
  availability_type      = coalesce(var.availability_type, local.profile.availability_type)
  disk_size_gb           = coalesce(var.disk_size_gb, local.profile.disk_size_gb)
  backup_retention_count = coalesce(var.backup_retention_count, local.profile.backup_retention_count)
  update_track           = coalesce(var.maintenance_window.update_track, local.profile.update_track)
  deletion_protection    = var.deletion_protection != null ? var.deletion_protection : local.profile.deletion_protection

  # Operational defaults that DBAs may tune per workload via var.database_flags
  default_operational_flags = {
    log_checkpoints            = "on"
    log_hostname               = "off"
    log_lock_waits             = "on"
    log_min_duration_statement = "1000"
    log_temp_files             = "10240"
  }

  # Security and auditing flags enforced everywhere (cannot be disabled)
  enforced_security_flags = {
    "cloudsql.enable_pgaudit"     = "on"
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "pgaudit.log"                 = join(",", [for c in split(",", var.pgaudit_log) : trimspace(c)])
    "pgaudit.log_parameter"       = "off"
  }

  primary_database_flags = merge(
    local.default_operational_flags,
    var.database_flags,
    local.enforced_security_flags,
  )

  # Standardized labels always present for inventory, cost attribution, and security auditing
  enforced_labels = {
    managed_by      = "opentofu"
    environment     = var.environment
    database_engine = "postgresql"
    instance        = var.name
  }

  primary_labels = merge(
    var.labels,
    local.enforced_labels,
    { role = "primary" },
  )

  # Read replica computed settings
  replica_names = {
    for k in keys(var.read_replicas) : k => "${local.instance_name}-${k}"
  }

  all_instance_names = concat(
    [local.instance_name],
    [for k in sort(keys(var.read_replicas)) : local.replica_names[k]],
  )

  # IAM principal maps
  # Cloud SQL requires service account usernames without the '.gserviceaccount.com' suffix.
  iam_service_account_usernames = {
    for sa in var.iam_service_accounts : sa => trimsuffix(sa, ".gserviceaccount.com")
  }

  iam_members = concat(
    [for u in sort(tolist(var.iam_users)) : "user:${u}"],
    [for sa in sort(tolist(var.iam_service_accounts)) : "serviceAccount:${sa}"],
    [for g in sort(tolist(var.iam_groups)) : "group:${g}"],
  )

  iam_roles_to_grant = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
  ]

  iam_bindings = var.grant_iam_roles ? {
    for pair in setproduct(local.iam_members, local.iam_roles_to_grant) :
    "${pair[0]}|${pair[1]}" => {
      member = pair[0]
      role   = pair[1]
    }
  } : {}

  # Scope project IAM bindings strictly to this Cloud SQL instance (and its read replicas)
  iam_condition_expression = join(" || ", [
    for inst in local.all_instance_names :
    "resource.name == \"projects/${data.google_client_config.current.project}/instances/${inst}\""
  ])
}
