# ---------------------------------------------------------------------------
# Cluster parameter groups (regional) with identical hardening in both regions:
# TLS enforced, SCRAM password hashing, pgaudit, connection/DDL/slow-query
# logging. Instances use the engine default instance parameter group.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.name}-"
  family      = local.pg_family
  description = "Aurora PostgreSQL ${local.engine_major} hardening for ${local.name}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
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

  name_prefix = "${local.name}-"
  family      = local.pg_family
  description = "Aurora PostgreSQL ${local.engine_major} hardening for ${local.name}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
