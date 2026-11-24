resource "aws_rds_cluster_parameter_group" "primary" {
  provider    = aws.primary
  name        = "${local.name_prefix}-${var.primary_region}-cluster-pg"
  family      = data.aws_rds_engine_version.postgresql.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${local.name_prefix} in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.merged_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-cluster-pg"
    Region = var.primary_region
  })
}

resource "aws_db_parameter_group" "primary" {
  provider    = aws.primary
  name        = "${local.name_prefix}-${var.primary_region}-instance-pg"
  family      = data.aws_rds_engine_version.postgresql.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${local.name_prefix} in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.merged_instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-instance-pg"
    Region = var.primary_region
  })
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-${var.secondary_region}-cluster-pg"
  family      = data.aws_rds_engine_version.postgresql.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${local.name_prefix} in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.merged_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-cluster-pg"
    Region = var.secondary_region
  })
}

resource "aws_db_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-${var.secondary_region}-instance-pg"
  family      = data.aws_rds_engine_version.postgresql.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${local.name_prefix} in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.merged_instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-instance-pg"
    Region = var.secondary_region
  })
}
