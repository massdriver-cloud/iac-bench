################################################################################
# Aurora PostgreSQL Global Database (Cross-Region RPO < 1s, RTO < 1 min)
################################################################################

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = local.deletion_protection
  force_destroy             = false
}

################################################################################
# KMS-Encrypted CloudWatch Log Groups (Pre-created for Encryption & Retention)
################################################################################

resource "aws_cloudwatch_log_group" "primary" {
  for_each = toset(local.cloudwatch_log_exports)

  name              = "/aws/rds/cluster/${local.primary_cluster_id}/${each.value}"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = {
    Name = "${local.primary_cluster_id}-${each.value}-logs"
    Role = "primary"
  }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary
  for_each = toset(local.cloudwatch_log_exports)

  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/${each.value}"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = {
    Name = "${local.secondary_cluster_id}-${each.value}-logs"
    Role = "secondary"
  }
}

################################################################################
# Primary Region Aurora PostgreSQL Cluster & Multi-AZ Instances
################################################################################

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.primary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  database_name  = aws_rds_global_cluster.this.database_name
  port           = var.port

  # Master credentials managed and rotated in AWS Secrets Manager (zero passwords in state)
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  # Network & security isolation
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  # Encryption & IAM database authentication for EKS workloads
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true

  # Continuous PITR backups, maintenance & deletion safety
  backup_retention_period      = local.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = local.deletion_protection
  skip_final_snapshot          = local.skip_final_snapshot
  final_snapshot_identifier    = local.skip_final_snapshot ? null : "${local.primary_cluster_id}-final"
  allow_major_version_upgrade  = var.allow_major_version_upgrade
  apply_immediately            = local.apply_immediately

  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.instance_class == "db.serverless" ? [1] : []
    content {
      min_capacity = 2.0
      max_capacity = 16.0
    }
  }

  depends_on = [aws_cloudwatch_log_group.primary]

  tags = {
    Name = local.primary_cluster_id
    Role = "primary"
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  # Deterministically spread instances across distinct private database AZs
  availability_zone       = local.primary_azs[count.index % length(local.primary_azs)]
  db_subnet_group_name    = aws_db_subnet_group.primary.name
  db_parameter_group_name = aws_db_parameter_group.primary.name
  publicly_accessible     = false
  ca_cert_identifier      = local.ca_cert_identifier

  # Deterministic failover priority (tier 0 writer, tier 1 first standby, tier 2+ readers)
  promotion_tier               = min(count.index, 15)
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  apply_immediately            = local.apply_immediately
  copy_tags_to_snapshot        = true
  preferred_maintenance_window = var.preferred_maintenance_window

  # Observability: Enhanced Monitoring + KMS-encrypted Performance Insights
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = local.pi_retention_period

  tags = {
    Name = "${local.primary_cluster_id}-${count.index + 1}"
    Role = count.index == 0 ? "primary-writer" : "primary-reader"
  }
}

################################################################################
# Secondary Region Aurora PostgreSQL Cluster & Warm Multi-AZ Instances
################################################################################

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  port           = var.port

  # Network & security isolation in secondary region's apps-<env> VPC
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  # Independent regional CMK encryption & IAM auth parity for seamless failover
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding

  # Continuous backups & safety parity (active immediately if promoted to primary)
  backup_retention_period      = local.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = local.deletion_protection
  skip_final_snapshot          = local.skip_final_snapshot
  final_snapshot_identifier    = local.skip_final_snapshot ? null : "${local.secondary_cluster_id}-final"
  allow_major_version_upgrade  = var.allow_major_version_upgrade
  apply_immediately            = local.apply_immediately

  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.secondary_instance_class == "db.serverless" ? [1] : []
    content {
      min_capacity = 2.0
      max_capacity = 16.0
    }
  }

  # AWS requires at least one primary DB instance to exist before creating a secondary cluster
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  # AWS populates replication_source_identifier on secondary global clusters after attachment
  lifecycle {
    ignore_changes = [replication_source_identifier]
  }

  tags = {
    Name = local.secondary_cluster_id
    Role = "secondary"
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = local.secondary_instance_class
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version

  # Deterministically spread warm secondary instances across distinct private database AZs
  availability_zone       = local.secondary_azs[count.index % length(local.secondary_azs)]
  db_subnet_group_name    = aws_db_subnet_group.secondary.name
  db_parameter_group_name = aws_db_parameter_group.secondary.name
  publicly_accessible     = false
  ca_cert_identifier      = local.ca_cert_identifier

  promotion_tier               = min(count.index, 15)
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  apply_immediately            = local.apply_immediately
  copy_tags_to_snapshot        = true
  preferred_maintenance_window = var.preferred_maintenance_window

  # Observability parity in secondary region
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = local.pi_retention_period

  tags = {
    Name = "${local.secondary_cluster_id}-${count.index + 1}"
    Role = count.index == 0 ? "secondary-standby-writer" : "secondary-reader"
  }
}

################################################################################
# Optional Read Replica Auto Scaling (Primary Region)
################################################################################

resource "aws_appautoscaling_target" "primary_read_replicas" {
  count = var.enable_read_replica_autoscaling ? 1 : 0

  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.primary.cluster_identifier}"
  min_capacity       = max(1, var.primary_instance_count - 1)
  max_capacity       = max(var.autoscaling_max_read_replicas, var.primary_instance_count - 1)
}

resource "aws_appautoscaling_policy" "primary_read_replicas_cpu" {
  count = var.enable_read_replica_autoscaling ? 1 : 0

  name               = "${local.primary_cluster_id}-read-replica-cpu"
  service_namespace  = aws_appautoscaling_target.primary_read_replicas[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.primary_read_replicas[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.primary_read_replicas[0].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    target_value       = var.autoscaling_target_cpu
    scale_in_cooldown  = 300
    scale_out_cooldown = 180
  }
}
