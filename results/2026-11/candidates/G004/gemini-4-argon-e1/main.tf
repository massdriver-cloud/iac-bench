locals {
  env_normalized = trimprefix(var.environment, "apps-")
  vpc_name       = "apps-${local.env_normalized}"

  name_prefix = "${var.service_name}-${local.env_normalized}"
  db_name     = coalesce(var.database_name, replace(var.service_name, "-", "_"))

  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major_version}"

  serverlessv2_scaling = var.serverlessv2_scaling_configuration != null ? var.serverlessv2_scaling_configuration : (
    var.instance_class == "db.serverless" ? {
      min_capacity = 2.0
      max_capacity = 16.0
    } : null
  )

  default_cluster_parameters = {
    "rds.force_ssl" = {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "immediate"
    }
    "log_connections" = {
      name         = "log_connections"
      value        = "1"
      apply_method = "immediate"
    }
    "log_disconnections" = {
      name         = "log_disconnections"
      value        = "1"
      apply_method = "immediate"
    }
    "log_ddl" = {
      name         = "log_ddl"
      value        = "1"
      apply_method = "immediate"
    }
    "log_min_duration_statement" = {
      name         = "log_min_duration_statement"
      value        = "1000"
      apply_method = "immediate"
    }
    "shared_preload_libraries" = {
      name         = "shared_preload_libraries"
      value        = "pg_stat_statements,pgaudit"
      apply_method = "pending-reboot"
    }
    "pgaudit.log" = {
      name         = "pgaudit.log"
      value        = "ddl,role"
      apply_method = "immediate"
    }
  }

  custom_cluster_parameters = {
    for p in var.cluster_parameters : p.name => {
      name         = p.name
      value        = p.value
      apply_method = coalesce(p.apply_method, "immediate")
    }
  }

  effective_cluster_parameters = merge(local.default_cluster_parameters, local.custom_cluster_parameters)

  default_instance_parameters = {
    "log_lock_waits" = {
      name         = "log_lock_waits"
      value        = "1"
      apply_method = "immediate"
    }
    "track_io_timing" = {
      name         = "track_io_timing"
      value        = "1"
      apply_method = "immediate"
    }
    "idle_in_transaction_session_timeout" = {
      name         = "idle_in_transaction_session_timeout"
      value        = "60000"
      apply_method = "immediate"
    }
  }

  iam_db_users = distinct(concat([var.service_name, replace(var.service_name, "-", "_"), var.master_username], var.db_users))

  primary_allowed_cidrs   = distinct(concat([data.aws_vpc.primary.cidr_block], coalesce(try(var.allowed_cidr_blocks.primary, null), [])))
  secondary_allowed_cidrs = distinct(concat([data.aws_vpc.secondary.cidr_block], coalesce(try(var.allowed_cidr_blocks.secondary, null), [])))

  primary_allowed_sgs   = toset(coalesce(try(var.allowed_security_group_ids.primary, null), []))
  secondary_allowed_sgs = toset(coalesce(try(var.allowed_security_group_ids.secondary, null), []))

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = local.env_normalized
      ManagedBy          = "opentofu"
      DataClassification = "confidential-pci-pii"
      DatabaseEngine     = "aurora-postgresql"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_partition" "current" {
  provider = aws.primary
}

data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_database" {
  provider = aws.primary

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

################################################################################
# KMS Encryption Keys (Primary and Secondary Regions)
################################################################################

data "aws_iam_policy_document" "kms_primary" {
  provider = aws.primary

  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "KMS key for ${local.name_prefix} Aurora PostgreSQL primary cluster, Secrets Manager, and logs (${var.primary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-aurora-${var.primary_region}"
    Region = var.primary_region
  })
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/aurora/${local.name_prefix}/${var.primary_region}"
  target_key_id = aws_kms_key.primary.key_id
}

data "aws_iam_policy_document" "kms_secondary" {
  provider = aws.secondary

  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "KMS key for ${local.name_prefix} Aurora PostgreSQL secondary cluster and logs (${var.secondary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-aurora-${var.secondary_region}"
    Region = var.secondary_region
  })
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/aurora/${local.name_prefix}/${var.secondary_region}"
  target_key_id = aws_kms_key.secondary.key_id
}

################################################################################
# Networking: DB Subnet Groups & Security Groups (Primary and Secondary)
################################################################################

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = "${local.name_prefix}-db-subnets-${var.primary_region}"
  description = "Private database subnets for ${local.name_prefix} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-db-subnets-${var.primary_region}"
    Region = var.primary_region
  })
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-db-subnets-${var.secondary_region}"
  description = "Private database subnets for ${local.name_prefix} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-db-subnets-${var.secondary_region}"
    Region = var.secondary_region
  })
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.name_prefix}-aurora-sg"
  description = "Security group for ${local.name_prefix} Aurora PostgreSQL cluster in ${var.primary_region}"
  vpc_id      = data.aws_vpc.primary.id

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-aurora-sg"
    Region = var.primary_region
  })
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  provider = aws.primary
  for_each = toset(local.primary_allowed_cidrs)

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL access from ${each.value}"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  provider = aws.primary
  for_each = local.primary_allowed_sgs

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL access from security group ${each.value}"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value

  tags = local.common_tags
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-aurora-sg"
  description = "Security group for ${local.name_prefix} Aurora PostgreSQL cluster in ${var.secondary_region}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-aurora-sg"
    Region = var.secondary_region
  })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(local.secondary_allowed_cidrs)

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL access from ${each.value}"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = local.secondary_allowed_sgs

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL access from security group ${each.value}"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value

  tags = local.common_tags
}

################################################################################
# Hardened Parameter Groups (Primary and Secondary)
################################################################################

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = "${local.name_prefix}-cluster-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.primary_region})"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-cluster-pg"
    Region = var.primary_region
  })
}

resource "aws_db_parameter_group" "primary" {
  provider = aws.primary

  name        = "${local.name_prefix}-instance-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${local.name_prefix} (${var.primary_region})"

  dynamic "parameter" {
    for_each = local.default_instance_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-instance-pg"
    Region = var.primary_region
  })
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-cluster-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.secondary_region})"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-cluster-pg"
    Region = var.secondary_region
  })
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-instance-pg"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${local.name_prefix} (${var.secondary_region})"

  dynamic "parameter" {
    for_each = local.default_instance_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-instance-pg"
    Region = var.secondary_region
  })
}

################################################################################
# CloudWatch Log Groups & Enhanced Monitoring IAM Role
################################################################################

resource "aws_cloudwatch_log_group" "primary_postgresql" {
  provider = aws.primary

  name              = "/aws/rds/cluster/${local.name_prefix}-${var.primary_region}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-postgresql-logs"
    Region = var.primary_region
  })
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.name_prefix}-${var.secondary_region}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-postgresql-logs"
    Region = var.secondary_region
  })
}

data "aws_iam_policy_document" "rds_enhanced_monitoring_assume" {
  provider = aws.primary

  statement {
    sid     = "AllowRDSMonitoringServiceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  provider = aws.primary

  name               = "${local.name_prefix}-rds-enhanced-monitoring"
  description        = "IAM role for RDS Enhanced Monitoring for ${local.name_prefix} Aurora Global Database"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  provider = aws.primary

  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# Aurora Global Database, Primary Cluster & Secondary Cluster
################################################################################

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.db_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-global"
  })
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = "${local.name_prefix}-${var.primary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  database_name             = local.db_name

  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.key_id

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  port                            = 5432

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.name_prefix}-${var.primary_region}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.serverlessv2_scaling != null ? [local.serverlessv2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}"
    Region = var.primary_region
    Role   = "primary"
  })

  depends_on = [aws_cloudwatch_log_group.primary_postgresql]

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region (${var.primary_region}) and secondary_region (${var.secondary_region}) must be two different AWS regions for cross-region disaster recovery."
    }
    precondition {
      condition     = length(data.aws_subnets.primary_database.ids) >= 2
      error_message = "At least 2 database subnets tagged tier=database must exist in VPC ${local.vpc_name} in ${var.primary_region}."
    }
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier                   = "${local.name_prefix}-${var.primary_region}-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.primary.id
  engine                       = aws_rds_cluster.primary.engine
  engine_version               = aws_rds_cluster.primary.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.primary.name
  db_parameter_group_name      = aws_db_parameter_group.primary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  ca_cert_identifier           = "rds-ca-rsa2048-g1"
  copy_tags_to_snapshot        = true
  promotion_tier               = count.index < 2 ? 0 : 1
  preferred_maintenance_window = var.preferred_maintenance_window

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-${count.index + 1}"
    Region = var.primary_region
  })
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.name_prefix}-${var.secondary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  port                            = 5432

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.name_prefix}-${var.secondary_region}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.serverlessv2_scaling != null ? [local.serverlessv2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}"
    Region = var.secondary_region
    Role   = "secondary"
  })

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary_postgresql
  ]

  lifecycle {
    ignore_changes = [
      replication_source_identifier
    ]
    precondition {
      condition     = length(data.aws_subnets.secondary_database.ids) >= 2
      error_message = "At least 2 database subnets tagged tier=database must exist in VPC ${local.vpc_name} in ${var.secondary_region}."
    }
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier                   = "${local.name_prefix}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.secondary.id
  engine                       = aws_rds_cluster.secondary.engine
  engine_version               = aws_rds_cluster.secondary.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.secondary.name
  db_parameter_group_name      = aws_db_parameter_group.secondary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  ca_cert_identifier           = "rds-ca-rsa2048-g1"
  copy_tags_to_snapshot        = true
  promotion_tier               = count.index < 2 ? 0 : 1
  preferred_maintenance_window = var.preferred_maintenance_window

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-${count.index + 1}"
    Region = var.secondary_region
  })
}

################################################################################
# EKS Service IAM Database Authentication Policy & Optional Role Attachments
################################################################################

data "aws_iam_policy_document" "db_connect" {
  provider = aws.primary

  statement {
    sid     = "AllowAuroraIAMDatabaseAuthPrimaryAndSecondary"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = flatten([
      for db_user in local.iam_db_users : [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${db_user}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${db_user}"
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect" {
  provider = aws.primary

  name        = "${local.name_prefix}-aurora-db-connect"
  description = "Allows EKS services to authenticate via IAM to ${local.name_prefix} Aurora PostgreSQL clusters in ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.db_connect.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "service_db_connect" {
  provider = aws.primary
  for_each = toset(var.service_iam_role_arns)

  role       = element(reverse(split("/", each.value)), 0)
  policy_arn = aws_iam_policy.db_connect.arn
}
