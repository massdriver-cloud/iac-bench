resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.name_prefix}-primary-cluster-"
  family      = local.parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.primary_region})"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-primary-cluster-pg"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-secondary-cluster-"
  family      = data.aws_rds_engine_version.secondary.parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.secondary_region})"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-secondary-cluster-pg"
  }
}

resource "aws_db_parameter_group" "primary" {
  name_prefix = "${local.name_prefix}-primary-db-"
  family      = local.parameter_group_family
  description = "Production Aurora PostgreSQL DB instance parameter group for ${local.name_prefix} (${var.primary_region})"

  dynamic "parameter" {
    for_each = var.extra_db_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-primary-db-pg"
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-secondary-db-"
  family      = data.aws_rds_engine_version.secondary.parameter_group_family
  description = "Production Aurora PostgreSQL DB instance parameter group for ${local.name_prefix} (${var.secondary_region})"

  dynamic "parameter" {
    for_each = var.extra_db_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-secondary-db-pg"
  }
}
