resource "aws_rds_global_cluster" "this" {
  region                    = var.primary_region
  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = local.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  tags = merge(local.common_tags, {
    Name = local.global_cluster_id
  })

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region (${var.primary_region}) and secondary_region (${var.secondary_region}) must be two distinct US AWS regions."
    }

    precondition {
      condition     = var.environment != "prod" || (var.primary_instance_count >= 2 && var.secondary_instance_count >= 2)
      error_message = "Production deployments require primary_instance_count >= 2 and secondary_instance_count >= 2 for Multi-AZ availability and rapid cross-region failover readiness."
    }

    precondition {
      condition     = length(local.primary_eligible_azs) >= 2 && length(local.secondary_eligible_azs) >= 2
      error_message = "Both primary (${var.primary_region}) and secondary (${var.secondary_region}) VPCs must provide private tier=database subnets in at least 2 Availability Zones supporting ${var.instance_class}."
    }

    precondition {
      condition     = !local.enable_read_autoscaling || (var.max_read_replica_count >= max(1, var.primary_instance_count - 1) && var.max_read_replica_count >= var.secondary_instance_count)
      error_message = "max_read_replica_count must be greater than or equal to the baseline reader counts in both regions."
    }
  }
}

resource "aws_rds_cluster" "primary" {
  region                              = var.primary_region
  cluster_identifier                  = local.primary_cluster_id
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  port                                = var.port
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  storage_type                        = var.storage_type
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = local.primary_backup_window
  preferred_maintenance_window        = local.primary_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${local.primary_cluster_id}-final"
  enabled_cloudwatch_logs_exports     = local.exported_logs
  apply_immediately                   = var.apply_immediately
  allow_major_version_upgrade         = false

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [var.serverlessv2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  tags = merge(local.common_tags, {
    Name         = local.primary_cluster_id
    cluster-role = "primary"
  })

  depends_on = [aws_cloudwatch_log_group.primary]
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  region                                = var.primary_region
  identifier                            = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  instance_class                        = var.instance_class
  availability_zone                     = local.primary_eligible_azs[count.index % length(local.primary_eligible_azs)]
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = aws_rds_cluster.primary.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  db_parameter_group_name               = aws_db_parameter_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  ca_cert_identifier                    = local.ca_cert_identifier
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
  promotion_tier                        = count.index
  copy_tags_to_snapshot                 = true
  apply_immediately                     = var.apply_immediately

  tags = merge(local.common_tags, {
    Name = "${local.primary_cluster_id}-${count.index + 1}"
  })

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

# Secondary regional cluster in the Aurora Global Database.
# Note: AWS RDS replicates database_name and master credentials at the storage layer from
# the primary cluster, and forbids final_snapshot_identifier on secondary global members.
resource "aws_rds_cluster" "secondary" {
  region                              = var.secondary_region
  cluster_identifier                  = local.secondary_cluster_id
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  port                                = var.port
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_replica_key.secondary.arn
  storage_type                        = var.storage_type
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = local.secondary_backup_window
  preferred_maintenance_window        = local.secondary_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = true
  enabled_cloudwatch_logs_exports     = local.exported_logs
  apply_immediately                   = var.apply_immediately
  allow_major_version_upgrade         = false

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [var.serverlessv2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  tags = merge(local.common_tags, {
    Name         = local.secondary_cluster_id
    cluster-role = "secondary"
  })

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  count = var.secondary_instance_count

  region                                = var.secondary_region
  identifier                            = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  instance_class                        = var.instance_class
  availability_zone                     = local.secondary_eligible_azs[count.index % length(local.secondary_eligible_azs)]
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  db_parameter_group_name               = aws_db_parameter_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  ca_cert_identifier                    = local.ca_cert_identifier
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_replica_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
  promotion_tier                        = count.index
  copy_tags_to_snapshot                 = true
  apply_immediately                     = var.apply_immediately

  tags = merge(local.common_tags, {
    Name = "${local.secondary_cluster_id}-${count.index + 1}"
  })

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

resource "aws_appautoscaling_target" "primary_readers" {
  count = local.enable_read_autoscaling ? 1 : 0

  region             = var.primary_region
  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.primary.id}"
  min_capacity       = max(1, var.primary_instance_count - 1)
  max_capacity       = var.max_read_replica_count
}

resource "aws_appautoscaling_policy" "primary_readers_cpu" {
  count = local.enable_read_autoscaling ? 1 : 0

  region             = var.primary_region
  name               = "${local.primary_cluster_id}-reader-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.primary_readers[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.primary_readers[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.primary_readers[0].resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    target_value       = var.read_autoscaling_target_cpu
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_target" "secondary_readers" {
  count = local.enable_read_autoscaling ? 1 : 0

  region             = var.secondary_region
  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.secondary.id}"
  min_capacity       = var.secondary_instance_count
  max_capacity       = var.max_read_replica_count
}

resource "aws_appautoscaling_policy" "secondary_readers_cpu" {
  count = local.enable_read_autoscaling ? 1 : 0

  region             = var.secondary_region
  name               = "${local.secondary_cluster_id}-reader-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.secondary_readers[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.secondary_readers[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.secondary_readers[0].resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    target_value       = var.read_autoscaling_target_cpu
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
