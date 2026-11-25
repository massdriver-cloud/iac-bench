locals {
  # Global cluster identifier, e.g. "payments-ledger-prod".
  name = "${var.service_name}-${var.environment}"

  # Regional cluster identifiers carry the region so they are unique and
  # obvious in the console, e.g. "payments-ledger-prod-us-east-1".
  primary_cluster_id   = "${local.name}-${var.primary_region}"
  secondary_cluster_id = "${local.name}-${var.secondary_region}"

  # The network team's VPC for this environment, in each region.
  vpc_name = "apps-${var.environment}"

  # Aurora parameter group family, e.g. "aurora-postgresql16".
  engine_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  # Endpoint behind the writer DNS record.
  writer_endpoint = var.writer_region == "primary" ? aws_rds_cluster.primary.endpoint : aws_rds_cluster.secondary.endpoint

  common_tags = merge(var.tags, {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "opentofu"
    Module      = "aurora-postgres-global"
  })
}
