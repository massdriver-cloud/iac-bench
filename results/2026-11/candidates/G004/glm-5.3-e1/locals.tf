locals {
  name    = "${var.service_name}-${var.environment}"
  is_prod = var.environment == "prod"

  engine = "aurora-postgresql"

  # Resolve the concrete engine version once so the global cluster and both
  # regional clusters always agree. With the default (null) this resolves to
  # the AWS default version for the primary region - always a creatable
  # version - and the parameter group family comes from the same lookup, so
  # the two can never disagree.
  engine_version         = data.aws_rds_engine_version.selected.version
  parameter_group_family = data.aws_rds_engine_version.selected.parameter_group_family

  vpc_name = coalesce(var.vpc_name, "apps-${var.environment}")

  # The initial database defaults to the service name, sanitised into a valid
  # PostgreSQL identifier (service_name is validated to contain only
  # lowercase letters, digits and hyphens).
  database_name = coalesce(var.database_name, lower(replace(var.service_name, "-", "_")))

  # Environment-aware sizing and posture defaults; every one of these can be
  # overridden per database.
  instance_class           = coalesce(var.instance_class, local.is_prod ? "db.r6g.large" : "db.t4g.medium")
  primary_instance_count   = coalesce(var.primary_instance_count, local.is_prod ? 2 : 1)
  secondary_instance_count = coalesce(var.secondary_instance_count, 1)
  backup_retention_period  = coalesce(var.backup_retention_period, local.is_prod ? 14 : 1)
  deletion_protection      = coalesce(var.deletion_protection, local.is_prod)
  skip_final_snapshot      = coalesce(var.skip_final_snapshot, !local.is_prod)
  secret_recovery_window   = local.is_prod ? 7 : 0

  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  # Database subnets: explicit IDs win, otherwise the network team's subnets
  # are discovered by tag inside the environment VPC of each region.
  primary_subnet_ids   = coalesce(var.primary_subnet_ids, try(data.aws_subnets.primary_database[0].ids, null))
  secondary_subnet_ids = coalesce(var.secondary_subnet_ids, try(data.aws_subnets.secondary_database[0].ids, null))

  # Cluster parameters. TLS is mandatory: these clusters hold customer and
  # payment data, and IAM database authentication uses it anyway.
  cluster_parameters = merge(
    { "rds.force_ssl" = "1" },
    var.cluster_parameters,
  )

  # Ingress sources. If a caller provides none at all, fall back to the
  # regional VPC's own CIDR - the database subnets are private and EKS pods
  # run inside the same VPC.
  primary_ingress_cidrs = length(concat(var.allowed_cidr_blocks, var.primary_allowed_security_group_ids)) > 0 ? var.allowed_cidr_blocks : [data.aws_vpc.primary.cidr_block]

  secondary_ingress_cidrs = length(concat(var.allowed_cidr_blocks, var.secondary_allowed_security_group_ids)) > 0 ? var.allowed_cidr_blocks : [data.aws_vpc.secondary.cidr_block]

  common_tags = merge(
    var.tags,
    {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Module      = "aurora-postgresql-global"
    },
  )
}
