# ------------------------------------------------------------------------------
# Primary Region Parameter Groups
# ------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.primary_cluster_id}-${local.primary_parameter_group_family}"
  family      = local.primary_parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameter group for ${local.primary_cluster_id}"

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
    Name = "${local.primary_cluster_id}-cluster-pg"
  }
}

resource "aws_db_parameter_group" "primary" {
  name        = "${local.primary_cluster_id}-instance-${local.primary_parameter_group_family}"
  family      = local.primary_parameter_group_family
  description = "Production Aurora PostgreSQL instance parameter group for ${local.primary_cluster_id}"

  dynamic "parameter" {
    for_each = local.instance_parameters
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
    Name = "${local.primary_cluster_id}-instance-pg"
  }
}

# ------------------------------------------------------------------------------
# Secondary Region Parameter Groups (identical config for seamless failover)
# ------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-${local.secondary_parameter_group_family}"
  family      = local.secondary_parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameter group for ${local.secondary_cluster_id}"

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
    Name = "${local.secondary_cluster_id}-cluster-pg"
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-instance-${local.secondary_parameter_group_family}"
  family      = local.secondary_parameter_group_family
  description = "Production Aurora PostgreSQL instance parameter group for ${local.secondary_cluster_id}"

  dynamic "parameter" {
    for_each = local.instance_parameters
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
    Name = "${local.secondary_cluster_id}-instance-pg"
  }
}
