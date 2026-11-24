# ---------------------------------------------------------------------------
# Cluster parameter groups. Parameter groups are regional, so an identical
# group exists in each region; both enforce TLS (rds.force_ssl) and basic
# connection auditing via the module's default parameters.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name_env}-aurora"
  family      = local.parameter_group_family
  description = "Cluster parameters for ${local.name_env} (${var.primary_region})."

  dynamic "parameter" {
    for_each = var.cluster_parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = {
    Name = "${local.name_env}-aurora"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.dr

  name        = "${local.name_env}-aurora"
  family      = local.parameter_group_family
  description = "Cluster parameters for ${local.secondary_cluster_id} (${var.secondary_region})."

  dynamic "parameter" {
    for_each = var.cluster_parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = {
    Name = "${local.name_env}-aurora"
  }
}
