################################################################################
# Regional Cluster & DB Parameter Groups
# Identical PostgreSQL security, auditing, and reliability settings in both
# regions so failover never degrades security posture or query guardrails.
################################################################################

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.name_prefix}-cpg-"
  family      = local.parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameters for ${local.name_prefix} (${var.primary_region})"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${local.primary_cluster_id}-cpg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.name_prefix}-dpg-"
  family      = local.parameter_group_family
  description = "Production Aurora PostgreSQL instance parameters for ${local.name_prefix} (${var.primary_region})"

  tags = {
    Name = "${local.primary_cluster_id}-dpg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-cpg-"
  family      = local.parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameters for ${local.name_prefix} (${var.secondary_region})"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${local.secondary_cluster_id}-cpg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-dpg-"
  family      = local.parameter_group_family
  description = "Production Aurora PostgreSQL instance parameters for ${local.name_prefix} (${var.secondary_region})"

  tags = {
    Name = "${local.secondary_cluster_id}-dpg"
  }

  lifecycle {
    create_before_destroy = true
  }
}
