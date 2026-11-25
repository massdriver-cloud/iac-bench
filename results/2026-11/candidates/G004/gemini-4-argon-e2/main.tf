data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

locals {
  env_short              = trimprefix(var.environment, "apps-")
  vpc_name               = startswith(var.environment, "apps-") ? var.environment : "apps-${var.environment}"
  name_prefix            = "${var.service_name}-${local.env_short}"
  global_cluster_id      = "${local.name_prefix}-global"
  primary_cluster_id     = "${local.name_prefix}-${var.primary_region}"
  secondary_cluster_id   = "${local.name_prefix}-${var.secondary_region}"
  database_name          = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  iam_database_user      = coalesce(var.iam_database_user, replace(var.service_name, "-", "_"))
  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major_version}"
  cloudwatch_log_exports = ["postgresql", "iam-db-auth-error"]

  default_cluster_parameters = {
    "rds.force_ssl"                       = { value = "1", apply_method = "pending-reboot" }
    "shared_preload_libraries"            = { value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
    "pgaudit.log"                         = { value = "ddl,role", apply_method = "immediate" }
    "log_connections"                     = { value = "1", apply_method = "immediate" }
    "log_disconnections"                  = { value = "1", apply_method = "immediate" }
    "log_statement"                       = { value = "ddl", apply_method = "immediate" }
    "log_min_duration_statement"          = { value = "1000", apply_method = "immediate" }
    "log_lock_waits"                      = { value = "1", apply_method = "immediate" }
    "idle_in_transaction_session_timeout" = { value = "60000", apply_method = "immediate" }
    "track_activity_query_size"           = { value = "4096", apply_method = "pending-reboot" }
  }

  custom_cluster_parameters = {
    for param in var.cluster_parameters : param.name => {
      value        = param.value
      apply_method = coalesce(param.apply_method, "immediate")
    }
  }

  effective_cluster_parameters = merge(local.default_cluster_parameters, local.custom_cluster_parameters)

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = local.env_short
      ManagedBy          = "opentofu"
      DataClassification = "confidential-customer-payment"
      Engine             = "aurora-postgresql"
    },
    var.tags
  )
}

# ------------------------------------------------------------------------------
# Subnet Groups (Primary & Secondary Regions)
# ------------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  name        = "${local.primary_cluster_id}-subnets"
  description = "Private database subnet group for ${var.service_name} (${local.env_short}) in ${var.primary_region}"
  subnet_ids  = sort(data.aws_subnets.primary_database.ids)

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be two distinct US AWS regions for cross-region disaster recovery."
    }

    precondition {
      condition     = length(data.aws_subnets.primary_database.ids) >= 2
      error_message = "At least two subnets tagged tier=database are required in the primary region VPC (${local.vpc_name} in ${var.primary_region})."
    }
  }

  tags = {
    Name   = "${local.primary_cluster_id}-subnets"
    Region = var.primary_region
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-subnets"
  description = "Private database subnet group for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"
  subnet_ids  = sort(data.aws_subnets.secondary_database.ids)

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary_database.ids) >= 2
      error_message = "At least two subnets tagged tier=database are required in the secondary region VPC (${local.vpc_name} in ${var.secondary_region})."
    }
  }

  tags = {
    Name   = "${local.secondary_cluster_id}-subnets"
    Region = var.secondary_region
  }
}

# ------------------------------------------------------------------------------
# Cluster & Instance Parameter Groups (Primary & Secondary Regions)
# ------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.primary_cluster_id}-cluster-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${var.service_name} (${local.env_short}) in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name   = "${local.primary_cluster_id}-cluster-pg"
    Region = var.primary_region
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-cluster-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name   = "${local.secondary_cluster_id}-cluster-pg"
    Region = var.secondary_region
  }
}

resource "aws_db_parameter_group" "primary" {
  name        = "${local.primary_cluster_id}-instance-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${var.service_name} (${local.env_short}) in ${var.primary_region}"

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name   = "${local.primary_cluster_id}-instance-pg"
    Region = var.primary_region
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-instance-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name   = "${local.secondary_cluster_id}-instance-pg"
    Region = var.secondary_region
  }
}

# ------------------------------------------------------------------------------
# Aurora Global Database & Regional Clusters
# ------------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = local.primary_cluster_id
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  db_instance_parameter_group_name    = aws_db_parameter_group.primary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${local.primary_cluster_id}-final-snapshot"
  apply_immediately                   = var.apply_immediately
  enabled_cloudwatch_logs_exports     = local.cloudwatch_log_exports

  serverlessv2_scaling_configuration {
    min_capacity = var.serverlessv2_min_capacity
    max_capacity = var.serverlessv2_max_capacity
  }

  depends_on = [
    aws_cloudwatch_log_group.primary
  ]

  tags = {
    Name        = local.primary_cluster_id
    ClusterRole = "primary"
    Region      = var.primary_region
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier                            = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = aws_rds_cluster.primary.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  db_parameter_group_name               = aws_db_parameter_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  apply_immediately                     = var.apply_immediately
  copy_tags_to_snapshot                 = true
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.primary.arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  promotion_tier                        = count.index == 0 ? 0 : 1

  tags = {
    Name        = "${local.primary_cluster_id}-${count.index + 1}"
    ClusterRole = "primary"
    Region      = var.primary_region
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier                  = local.secondary_cluster_id
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  db_instance_parameter_group_name    = aws_db_parameter_group.secondary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  source_region                       = var.primary_region
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${local.secondary_cluster_id}-final-snapshot"
  apply_immediately                   = var.apply_immediately
  enabled_cloudwatch_logs_exports     = local.cloudwatch_log_exports

  serverlessv2_scaling_configuration {
    min_capacity = var.serverlessv2_min_capacity
    max_capacity = var.serverlessv2_max_capacity
  }

  depends_on = [
    aws_rds_cluster.primary,
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary
  ]

  lifecycle {
    ignore_changes = [
      replication_source_identifier
    ]
  }

  tags = {
    Name        = local.secondary_cluster_id
    ClusterRole = "secondary"
    Region      = var.secondary_region
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier                            = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = aws_rds_cluster.secondary.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  db_parameter_group_name               = aws_db_parameter_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  apply_immediately                     = var.apply_immediately
  copy_tags_to_snapshot                 = true
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.secondary.arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  promotion_tier                        = count.index == 0 ? 0 : 1

  tags = {
    Name        = "${local.secondary_cluster_id}-${count.index + 1}"
    ClusterRole = "secondary"
    Region      = var.secondary_region
  }
}
