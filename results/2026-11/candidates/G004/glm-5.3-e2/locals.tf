locals {
  # Every resource is named "<name>-<environment>-..." so that staging and prod
  # deployments of this module can coexist in the same AWS account.
  name    = "${var.name}-${var.environment}"
  is_prod = var.environment == "prod"

  # ---------------------------------------------------------------------------
  # Engine
  # ---------------------------------------------------------------------------
  engine           = "aurora-postgresql"
  engine_version   = data.aws_rds_engine_version.aurora_postgresql.version
  parameter_family = "${local.engine}${element(split(".", local.engine_version), 0)}"

  # Aurora Serverless v2 is opt-in via instance_class = "db.serverless".
  is_serverless = strcontains(var.instance_class, "serverless")

  # ---------------------------------------------------------------------------
  # Environment-aware operational defaults. Explicit inputs always win.
  # ---------------------------------------------------------------------------
  instance_count           = coalesce(var.instance_count, local.is_prod ? 2 : 1)
  secondary_instance_count = coalesce(var.secondary_instance_count, local.is_prod ? 2 : 1)
  deletion_protection      = coalesce(var.deletion_protection, local.is_prod)
  backup_retention_period  = coalesce(var.backup_retention_period, local.is_prod ? 30 : 7)
  skip_final_snapshot      = coalesce(var.skip_final_snapshot, !local.is_prod)

  pgaudit_log_csv = join(",", var.pgaudit_log)

  # ---------------------------------------------------------------------------
  # Tags
  # ---------------------------------------------------------------------------
  default_tags = merge(
    var.tags,
    {
      Service     = var.name
      Environment = var.environment
      Module      = "aurora-global-postgresql"
      ManagedBy   = "opentofu"
    }
  )

  # ---------------------------------------------------------------------------
  # Network discovery (see data.tf)
  # ---------------------------------------------------------------------------
  vpc_name = var.vpc_name != "" ? var.vpc_name : "apps-${var.environment}"

  primary_subnet_override   = try(var.subnet_ids["primary"], [])
  secondary_subnet_override = try(var.subnet_ids["secondary"], [])

  # The environment VPC is identified by its Name tag ("apps-<environment>");
  # environment-style tags are accepted as a fallback so the module keeps
  # working if the network team's tagging scheme evolves. Exactly one VPC must
  # match in each region.
  primary_discovered_vpc_id = one(distinct(concat(
    [for v in data.aws_vpc.primary_candidates : v.id if try(v.tags["Name"], "") == local.vpc_name],
    [for v in data.aws_vpc.primary_candidates : v.id if try(v.tags["Name"], "") == var.environment],
    [for v in data.aws_vpc.primary_candidates : v.id if try(v.tags["Environment"], "") == var.environment],
    [for v in data.aws_vpc.primary_candidates : v.id if try(v.tags["environment"], "") == var.environment],
    [for v in data.aws_vpc.primary_candidates : v.id if try(v.tags["env"], "") == var.environment]
  )))

  secondary_discovered_vpc_id = one(distinct(concat(
    [for v in data.aws_vpc.secondary_candidates : v.id if try(v.tags["Name"], "") == local.vpc_name],
    [for v in data.aws_vpc.secondary_candidates : v.id if try(v.tags["Name"], "") == var.environment],
    [for v in data.aws_vpc.secondary_candidates : v.id if try(v.tags["Environment"], "") == var.environment],
    [for v in data.aws_vpc.secondary_candidates : v.id if try(v.tags["environment"], "") == var.environment],
    [for v in data.aws_vpc.secondary_candidates : v.id if try(v.tags["env"], "") == var.environment]
  )))

  primary_subnet_ids   = length(local.primary_subnet_override) > 0 ? local.primary_subnet_override : try(data.aws_subnets.primary_database[0].ids, [])
  secondary_subnet_ids = length(local.secondary_subnet_override) > 0 ? local.secondary_subnet_override : try(data.aws_subnets.secondary_database[0].ids, [])

  # When subnets are supplied explicitly, the VPC is inferred from them;
  # otherwise it is the discovered environment VPC.
  primary_vpc_id   = length(local.primary_subnet_override) > 0 ? [for s in data.aws_subnet.primary_database : s.vpc_id][0] : local.primary_discovered_vpc_id
  secondary_vpc_id = length(local.secondary_subnet_override) > 0 ? [for s in data.aws_subnet.secondary_database : s.vpc_id][0] : local.secondary_discovered_vpc_id

  primary_vpc_cidr   = try(data.aws_vpc.primary_candidates[local.primary_vpc_id].cidr_block, "")
  secondary_vpc_cidr = try(data.aws_vpc.secondary_candidates[local.secondary_vpc_id].cidr_block, "")

  # Ingress rules for the database security groups. When no security groups or
  # CIDRs are supplied, allow the environment VPC's own CIDR so that services
  # in the same VPC can reach the database out of the box. Tighten this by
  # setting allowed_security_group_ids to your EKS security groups.
  primary_ingress_cidrs = distinct(concat(
    var.allowed_cidr_blocks,
    (length(var.allowed_security_group_ids) + length(var.allowed_cidr_blocks)) > 0 || local.primary_vpc_cidr == "" ? [] : [local.primary_vpc_cidr]
  ))

  secondary_ingress_cidrs = distinct(concat(
    var.secondary_allowed_cidr_blocks,
    (length(var.secondary_allowed_security_group_ids) + length(var.secondary_allowed_cidr_blocks)) > 0 || local.secondary_vpc_cidr == "" ? [] : [local.secondary_vpc_cidr]
  ))
}
