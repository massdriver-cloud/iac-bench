locals {
  engine = "aurora-postgresql"

  # Stable naming: <service>-<environment> everywhere, with the global role
  # appended for the two cluster members. The role names describe the initial
  # provisioning roles — after a failover they are historical, but identifiers
  # are kept stable so endpoints, log groups, and policies never churn.
  name                         = "${var.service_name}-${var.environment}"
  global_cluster_identifier    = "${local.name}-global"
  primary_cluster_identifier   = "${local.name}-primary"
  secondary_cluster_identifier = "${local.name}-secondary"

  # The network team's VPC for this environment (apps-staging / apps-prod).
  vpc_name = coalesce(var.vpc_name, "apps-${var.environment}")

  # Production-safe defaults the module owns, so service teams don't have to
  # remember them: deletion protection is automatic in prod, opt-in elsewhere.
  is_prod             = var.environment == "prod"
  deletion_protection = coalesce(var.deletion_protection, local.is_prod)

  engine_major           = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major}"
  pgaudit_log            = join(",", var.pgaudit_log_classes)
  log_exports            = ["audit", "postgresql"]

  # Resolve the network team's VPC in each region, either by its Name tag
  # (the standard convention) or via an explicit ID override.
  primary_vpc   = var.primary_vpc_id != null ? data.aws_vpc.primary_by_id[0] : data.aws_vpc.primary_by_name[0]
  secondary_vpc = var.secondary_vpc_id != null ? data.aws_vpc.secondary_by_id[0] : data.aws_vpc.secondary_by_name[0]

  # Cluster storage and the master-user secret use a customer-managed key; use
  # the caller's key when provided, otherwise the module's own (rotating) key.
  primary_kms_key_arn = coalesce(var.kms_key_arn, one(aws_kms_key.primary[*].arn))

  common_tags = merge(
    var.tags,
    {
      Service            = var.service_name
      Environment        = var.environment
      DataClassification = var.data_classification
      ManagedBy          = "opentofu"
    },
  )
}
