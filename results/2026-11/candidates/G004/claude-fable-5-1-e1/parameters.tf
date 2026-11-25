############################################
# Parameter groups — identical in both regions so a failover changes nothing
############################################

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.primary_cluster_id}-"
  family      = local.parameter_group_family
  description = "Cluster parameters for ${local.name} (${var.primary_region})"

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
}

resource "aws_db_parameter_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.primary_cluster_id}-"
  family      = local.parameter_group_family
  description = "Instance parameters for ${local.name} (${var.primary_region})"

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
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.secondary_cluster_id}-"
  family      = local.parameter_group_family
  description = "Cluster parameters for ${local.name} (${var.secondary_region})"

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
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.secondary_cluster_id}-"
  family      = local.parameter_group_family
  description = "Instance parameters for ${local.name} (${var.secondary_region})"

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
}
