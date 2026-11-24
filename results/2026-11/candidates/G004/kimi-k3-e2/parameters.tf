# Cluster parameter groups — the module owns database defaults so platform
# engineers don't have to be PostgreSQL specialists. Parameter groups are
# regional, so an identical one is created in each region. The name embeds the
# engine major version so major upgrades can create a new family safely.

resource "aws_rds_cluster_parameter_group" "primary" {
  provider    = aws.primary
  name        = "${local.base_name}-pg${local.engine_major}-cluster"
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${local.base_name}"

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
  provider    = aws.secondary
  name        = "${local.base_name}-pg${local.engine_major}-cluster"
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${local.base_name}"

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
