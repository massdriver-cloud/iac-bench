# ---------------------------------------------------------------------------
# Cluster parameter groups (one per region; they are region-scoped)
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws

  name        = local.stack
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${var.name} (${var.environment})"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = {
    Name = local.stack
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = local.stack
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${var.name} (${var.environment})"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = {
    Name = local.stack
  }
}
