locals {
  is_prod = var.environment == "prod"

  # Standardized identifiers within AWS RDS 63-character limits
  name_prefix          = "${var.service_name}-${var.environment}"
  global_cluster_id    = "${local.name_prefix}-global"
  primary_cluster_id   = "${local.name_prefix}-${var.primary_region}"
  secondary_cluster_id = "${local.name_prefix}-${var.secondary_region}"
  vpc_name             = "apps-${var.environment}"

  # Database & IAM user defaults
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  iam_db_users  = length(var.iam_db_users) > 0 ? var.iam_db_users : [local.database_name]

  # Engine & parameter group family
  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major_version}"

  # Secondary compute sizing defaults to primary so failover has full production capacity
  secondary_instance_class = coalesce(var.secondary_instance_class, var.instance_class)

  # Production-hardened defaults (safe in prod, ergonomic in staging, always overridable)
  deletion_protection     = coalesce(var.deletion_protection, local.is_prod)
  skip_final_snapshot     = coalesce(var.skip_final_snapshot, !local.is_prod)
  apply_immediately       = coalesce(var.apply_immediately, !local.is_prod)
  backup_retention_period = coalesce(var.backup_retention_period, local.is_prod ? 35 : 7)
  log_retention_days      = coalesce(var.log_retention_days, local.is_prod ? 365 : 30)
  pi_retention_period     = coalesce(var.performance_insights_retention_period, local.is_prod ? 93 : 7)
  cloudwatch_log_exports  = ["postgresql", "iam-db-auth-error"]
  ca_cert_identifier      = "rds-ca-rsa2048-g1"

  # Sorted distinct AZs from the network team's private database subnets for deterministic Multi-AZ spread
  primary_azs   = sort(distinct([for s in data.aws_subnet.primary_database : s.availability_zone]))
  secondary_azs = sort(distinct([for s in data.aws_subnet.secondary_database : s.availability_zone]))

  # Smart ~10% RAM FreeableMemory threshold (in bytes) based on instance size suffix
  instance_ram_gib_by_size = {
    "large"    = 16
    "xlarge"   = 32
    "2xlarge"  = 64
    "4xlarge"  = 128
    "8xlarge"  = 256
    "12xlarge" = 384
    "16xlarge" = 512
    "24xlarge" = 768
  }
  primary_size_suffix   = try(element(split(".", var.instance_class), 2), "")
  secondary_size_suffix = try(element(split(".", local.secondary_instance_class), 2), "")

  primary_freeable_memory_threshold_bytes = coalesce(
    var.freeable_memory_alarm_threshold_bytes,
    floor(lookup(local.instance_ram_gib_by_size, local.primary_size_suffix, 10) * 0.10 * 1073741824)
  )
  secondary_freeable_memory_threshold_bytes = coalesce(
    var.freeable_memory_alarm_threshold_bytes,
    floor(lookup(local.instance_ram_gib_by_size, local.secondary_size_suffix, 10) * 0.10 * 1073741824)
  )

  # Regional SNS topic ARNs (caller-supplied or module-created KMS-encrypted topics)
  primary_sns_topic_arn   = var.primary_alarm_sns_topic_arn != null ? var.primary_alarm_sns_topic_arn : aws_sns_topic.primary_alerts[0].arn
  secondary_sns_topic_arn = var.secondary_alarm_sns_topic_arn != null ? var.secondary_alarm_sns_topic_arn : aws_sns_topic.secondary_alerts[0].arn

  # Common tags applied via provider default_tags across both regions
  common_tags = merge(
    {
      ManagedBy          = "opentofu"
      Service            = var.service_name
      Environment        = var.environment
      OwnerTeam          = var.owner_team
      DataClassification = var.data_classification
      DatabaseEngine     = "aurora-postgresql"
      GlobalCluster      = local.global_cluster_id
    },
    var.tags
  )
}

check "distinct_regions" {
  assert {
    condition     = var.primary_region != var.secondary_region
    error_message = "primary_region and secondary_region must be different AWS regions to provide regional disaster recovery."
  }
}
