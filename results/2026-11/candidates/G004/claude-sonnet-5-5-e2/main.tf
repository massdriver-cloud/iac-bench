locals {
  identifier = "${var.name}-${var.environment}"
  vpc_name   = "apps-${var.environment}"

  # aurora-postgresql16 etc.
  parameter_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  default_tags = merge(var.tags, {
    Service     = var.name
    Environment = var.environment
    ManagedBy   = "opentofu"
    DataClass   = "customer-payment"
  })

  cluster_parameters = {
    # Customer/payment data: refuse unencrypted connections.
    "rds.force_ssl" = { value = "1", apply_method = "immediate" }
    # Audit-friendly connection logging and slow-query visibility.
    "log_connections"            = { value = "1", apply_method = "immediate" }
    "log_disconnections"         = { value = "1", apply_method = "immediate" }
    "log_min_duration_statement" = { value = "1000", apply_method = "immediate" }
  }
}

# -----------------------------------------------------------------------------
# Network lookups (owned by the network team)
# -----------------------------------------------------------------------------

data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    tier = "database"
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    tier = "database"
  }
}

# -----------------------------------------------------------------------------
# Encryption: one customer-managed key per region (a global database's
# secondary must use a key in its own region).
# -----------------------------------------------------------------------------

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "Aurora ${local.identifier} (primary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${local.identifier}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora ${local.identifier} (secondary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.identifier}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}

# -----------------------------------------------------------------------------
# Networking: subnet groups and security groups
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name       = local.identifier
  subnet_ids = data.aws_subnets.primary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary.ids) >= 2
      error_message = "Expected at least 2 subnets tagged tier=database in ${local.vpc_name} (primary region)."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name       = local.identifier
  subnet_ids = data.aws_subnets.secondary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary.ids) >= 2
      error_message = "Expected at least 2 subnets tagged tier=database in ${local.vpc_name} (secondary region)."
    }
  }
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.identifier}-aurora-"
  description = "Aurora ${local.identifier} PostgreSQL access"
  vpc_id      = data.aws_vpc.primary.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.identifier}-aurora-"
  description = "Aurora ${local.identifier} PostgreSQL access"
  vpc_id      = data.aws_vpc.secondary.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  provider = aws.primary
  for_each = toset(var.primary_client_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from client security group"
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider = aws.secondary
  for_each = toset(var.secondary_client_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from client security group"
}

# -----------------------------------------------------------------------------
# Parameter groups
# -----------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.identifier}-"
  family      = local.parameter_group_family
  description = "Aurora ${local.identifier} cluster parameters"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.identifier}-"
  family      = local.parameter_group_family
  description = "Aurora ${local.identifier} cluster parameters"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Aurora Global Database: primary writer cluster + warm secondary cluster
# -----------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true

  lifecycle {
    # Engine version is bumped deliberately; the member clusters track it.
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = "${local.identifier}-${var.primary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  database_name             = var.database_name

  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.identifier}-${var.primary_region}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    ignore_changes = [engine_version, global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier         = "${local.identifier}-${var.primary_region}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false

  auto_minor_version_upgrade            = false
  copy_tags_to_snapshot                 = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.identifier}-${var.secondary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version

  # Credentials and initial database come from the primary via replication.
  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:07:00-sun:08:00"
  copy_tags_to_snapshot        = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.identifier}-${var.secondary_region}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  # The secondary can only join once the primary has a writer.
  depends_on = [aws_rds_cluster_instance.primary]

  lifecycle {
    ignore_changes = [engine_version, global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.identifier}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  publicly_accessible  = false

  auto_minor_version_upgrade            = false
  copy_tags_to_snapshot                 = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  lifecycle {
    ignore_changes = [engine_version]
  }
}
