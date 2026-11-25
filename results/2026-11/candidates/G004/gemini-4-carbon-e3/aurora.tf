# -----------------------------------------------------------------------------
# Cluster & Instance Parameter Groups (Primary & Secondary Regions)
# -----------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  region      = var.primary_region
  name_prefix = "${local.primary_cluster_id}-cluster-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameters (TLS, pgaudit, SCRAM) for ${var.service_name} (${var.environment}) in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name   = "${local.primary_cluster_id}-cluster-params"
    region = var.primary_region
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "primary" {
  region      = var.primary_region
  name_prefix = "${local.primary_cluster_id}-instance-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameters for ${var.service_name} (${var.environment}) in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name   = "${local.primary_cluster_id}-instance-params"
    region = var.primary_region
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  region      = var.secondary_region
  name_prefix = "${local.secondary_cluster_id}-cluster-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameters (TLS, pgaudit, SCRAM) for ${var.service_name} (${var.environment}) in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-cluster-params"
    region = var.secondary_region
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "secondary" {
  region      = var.secondary_region
  name_prefix = "${local.secondary_cluster_id}-instance-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameters for ${var.service_name} (${var.environment}) in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-instance-params"
    region = var.secondary_region
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Aurora Global Database
# -----------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  region                    = var.primary_region
  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = local.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  tags = merge(local.tags, {
    Name = local.global_cluster_id
  })
}

# -----------------------------------------------------------------------------
# Primary Regional Aurora Cluster & Multi-AZ Instances
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  region                              = var.primary_region
  cluster_identifier                  = local.primary_cluster_id
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = aws_rds_global_cluster.this.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = local.primary_kms_key_arn
  port                                = var.port
  storage_encrypted                   = true
  kms_key_id                          = local.primary_kms_key_arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${local.primary_cluster_id}-final"
  apply_immediately               = var.apply_immediately
  enabled_cloudwatch_logs_exports = local.log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [1] : []
    content {
      min_capacity = var.serverlessv2_min_capacity
      max_capacity = var.serverlessv2_max_capacity
    }
  }

  tags = merge(local.tags, {
    Name         = local.primary_cluster_id
    region       = var.primary_region
    cluster-role = "primary"
  })

  depends_on = [aws_cloudwatch_log_group.primary]
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  region                  = var.primary_region
  identifier              = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.primary.id
  engine                  = aws_rds_cluster.primary.engine
  engine_version          = aws_rds_cluster.primary.engine_version
  instance_class          = var.instance_class
  db_subnet_group_name    = aws_db_subnet_group.primary.name
  db_parameter_group_name = aws_db_parameter_group.primary.name

  publicly_accessible        = false
  promotion_tier             = count.index == 0 ? 0 : 1
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.primary_kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  tags = merge(local.tags, {
    Name   = "${local.primary_cluster_id}-${count.index + 1}"
    region = var.primary_region
  })

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

# -----------------------------------------------------------------------------
# Secondary Regional Aurora Cluster & Warm Standby Multi-AZ Instances
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  region                              = var.secondary_region
  cluster_identifier                  = local.secondary_cluster_id
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  port                                = var.port
  storage_encrypted                   = true
  kms_key_id                          = local.secondary_kms_key_arn
  storage_type                        = var.storage_type
  enable_global_write_forwarding      = var.enable_global_write_forwarding
  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = true
  apply_immediately               = var.apply_immediately
  enabled_cloudwatch_logs_exports = local.log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [1] : []
    content {
      min_capacity = var.serverlessv2_min_capacity
      max_capacity = var.serverlessv2_max_capacity
    }
  }

  tags = merge(local.tags, {
    Name         = local.secondary_cluster_id
    region       = var.secondary_region
    cluster-role = "secondary"
  })

  # AWS requires at least one primary writer DB instance to exist before a
  # secondary regional cluster can join the Aurora Global Database.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  count = var.secondary_instance_count

  region                  = var.secondary_region
  identifier              = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.secondary.id
  engine                  = aws_rds_cluster.secondary.engine
  engine_version          = aws_rds_cluster.secondary.engine_version
  instance_class          = var.instance_class
  db_subnet_group_name    = aws_db_subnet_group.secondary.name
  db_parameter_group_name = aws_db_parameter_group.secondary.name

  publicly_accessible        = false
  promotion_tier             = count.index == 0 ? 0 : 1
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.secondary_kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-${count.index + 1}"
    region = var.secondary_region
  })

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

# -----------------------------------------------------------------------------
# Optional Route 53 DNS Records for Service Discovery & Fast Failover
# -----------------------------------------------------------------------------

resource "aws_route53_record" "writer" {
  count = var.route53_zone_id != null && var.route53_domain_suffix != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "${var.service_name}-db.${var.environment}.${var.route53_domain_suffix}"
  type    = "CNAME"
  ttl     = 60
  records = [coalesce(try(aws_rds_global_cluster.this.endpoint, null), aws_rds_cluster.primary.endpoint)]
}

resource "aws_route53_record" "primary_reader" {
  count = var.route53_zone_id != null && var.route53_domain_suffix != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "${var.service_name}-db-ro.${var.primary_region}.${var.environment}.${var.route53_domain_suffix}"
  type    = "CNAME"
  ttl     = 60
  records = [aws_rds_cluster.primary.reader_endpoint]
}

resource "aws_route53_record" "secondary_reader" {
  count = var.route53_zone_id != null && var.route53_domain_suffix != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "${var.service_name}-db-ro.${var.secondary_region}.${var.environment}.${var.route53_domain_suffix}"
  type    = "CNAME"
  ttl     = 60
  records = [aws_rds_cluster.secondary.reader_endpoint]
}
