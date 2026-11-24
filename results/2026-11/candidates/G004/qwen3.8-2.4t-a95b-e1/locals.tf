locals {
  # Base name shared by every resource: "<service>-<environment>".
  name_env = "${var.name}-${var.environment}"

  global_cluster_id    = "${local.name_env}-global"
  primary_cluster_id   = local.name_env
  secondary_cluster_id = "${local.name_env}-dr"

  # Network team naming convention: one VPC per environment per region.
  vpc_name = coalesce(var.vpc_name, "apps-${var.environment}")

  # PostgreSQL identifiers cannot contain hyphens.
  database_name = coalesce(var.database_name, replace(var.name, "-", "_"))

  # e.g. "16.4" -> "aurora-postgresql16"
  parameter_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  postgres_port = 5432

  common_tags = merge(
    {
      Service            = var.name
      Environment        = var.environment
      ManagedBy          = "opentofu"
      DataClassification = "confidential"
    },
    var.tags,
  )

  # IAM database authentication resource ARNs (one per cluster resource id,
  # for the master user the workloads connect as).
  primary_dbuser_arn   = "arn:${data.aws_partition.current.partition}:rds-db:${data.aws_region.primary.region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.master_username}"
  secondary_dbuser_arn = "arn:${data.aws_partition.current.partition}:rds-db:${data.aws_region.secondary.region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.master_username}"
}
