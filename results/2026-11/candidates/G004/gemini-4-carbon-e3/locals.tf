locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  vpc_name      = "apps-${var.environment}"
  name_prefix   = "${var.service_name}-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))

  global_cluster_id    = "${local.name_prefix}-global"
  primary_cluster_id   = "${local.name_prefix}-${var.primary_region}"
  secondary_cluster_id = "${local.name_prefix}-${var.secondary_region}"

  engine_version         = data.aws_rds_engine_version.primary.version_actual
  parameter_group_family = data.aws_rds_engine_version.primary.parameter_group_family

  is_serverless = var.instance_class == "db.serverless"

  create_primary_kms_key   = var.kms_key_arns.primary == null
  create_secondary_kms_key = var.kms_key_arns.secondary == null

  primary_kms_key_arn   = local.create_primary_kms_key ? aws_kms_key.primary[0].arn : var.kms_key_arns.primary
  secondary_kms_key_arn = local.create_secondary_kms_key ? aws_kms_key.secondary[0].arn : var.kms_key_arns.secondary

  primary_has_explicit_ingress   = length(var.allowed_security_group_ids.primary) > 0 || length(var.allowed_cidr_blocks.primary) > 0
  secondary_has_explicit_ingress = length(var.allowed_security_group_ids.secondary) > 0 || length(var.allowed_cidr_blocks.secondary) > 0

  enable_primary_vpc_cidr_ingress   = coalesce(var.allow_vpc_cidr_ingress, !local.primary_has_explicit_ingress)
  enable_secondary_vpc_cidr_ingress = coalesce(var.allow_vpc_cidr_ingress, !local.secondary_has_explicit_ingress)

  log_exports = ["postgresql", "iam-db-auth-error", "instance"]

  iam_db_users = length(var.iam_database_users) > 0 ? var.iam_database_users : [
    local.database_name,
    "${local.database_name}_app",
    "${local.database_name}_readonly",
  ]

  # Baseline cluster-level security & PCI/PII audit parameters
  baseline_cluster_parameters = {
    "rds.force_ssl"                       = { value = "1", apply_method = "pending-reboot" }
    "shared_preload_libraries"            = { value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
    "password_encryption"                 = { value = "scram-sha-256", apply_method = "immediate" }
    "pgaudit.log"                         = { value = "ddl,role", apply_method = "immediate" }
    "pgaudit.log_catalog"                 = { value = "0", apply_method = "immediate" }
    "log_connections"                     = { value = "1", apply_method = "immediate" }
    "log_disconnections"                  = { value = "1", apply_method = "immediate" }
    "log_lock_waits"                      = { value = "1", apply_method = "immediate" }
    "log_statement"                       = { value = "ddl", apply_method = "immediate" }
    "log_min_duration_statement"          = { value = "1000", apply_method = "immediate" }
    "idle_in_transaction_session_timeout" = { value = "60000", apply_method = "immediate" }
  }

  additional_cluster_parameters_map = {
    for p in var.additional_cluster_parameters : p.name => {
      value        = p.value
      apply_method = p.apply_method
    }
  }

  effective_cluster_parameters = merge(
    local.baseline_cluster_parameters,
    local.additional_cluster_parameters_map,
  )

  # Instance-level parameters ensuring uniform query/connection telemetry across all readers & writers
  instance_parameters = {
    "log_connections"            = { value = "1", apply_method = "immediate" }
    "log_disconnections"         = { value = "1", apply_method = "immediate" }
    "log_lock_waits"             = { value = "1", apply_method = "immediate" }
    "log_min_duration_statement" = { value = "1000", apply_method = "immediate" }
    "pg_stat_statements.track"   = { value = "top", apply_method = "immediate" }
  }

  default_tags = {
    service             = var.service_name
    environment         = var.environment
    managed-by          = "opentofu"
    module              = "aurora-postgresql-global"
    data-classification = "confidential-customer-payment"
  }

  tags = merge(local.default_tags, var.tags)
}
