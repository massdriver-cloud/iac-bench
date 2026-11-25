locals {
  default_cluster_parameters = [
    {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_connections"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_disconnections"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_statement"
      value        = "ddl"
      apply_method = "immediate"
    },
    {
      name         = "log_min_duration_statement"
      value        = "1000"
      apply_method = "immediate"
    }
  ]

  custom_cluster_param_names = [for p in var.custom_cluster_parameters : p.name]
  effective_default_cluster_params = [
    for p in local.default_cluster_parameters : p
    if !contains(local.custom_cluster_param_names, p.name)
  ]
  all_cluster_parameters = concat(local.effective_default_cluster_params, var.custom_cluster_parameters)
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${var.name}-primary-cluster-pg"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL cluster parameter group for ${var.name} in primary region"

  dynamic "parameter" {
    for_each = local.all_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = try(parameter.value.apply_method, "immediate")
    }
  }

  tags = local.primary_tags
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-secondary-cluster-pg"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL cluster parameter group for ${var.name} in secondary region"

  dynamic "parameter" {
    for_each = local.all_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = try(parameter.value.apply_method, "immediate")
    }
  }

  tags = local.secondary_tags
}

resource "aws_db_parameter_group" "primary" {
  name        = "${var.name}-primary-instance-pg"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL DB instance parameter group for ${var.name} in primary region"

  dynamic "parameter" {
    for_each = var.custom_db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = try(parameter.value.apply_method, "immediate")
    }
  }

  tags = local.primary_tags
}

resource "aws_db_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-secondary-instance-pg"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL DB instance parameter group for ${var.name} in secondary region"

  dynamic "parameter" {
    for_each = var.custom_db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = try(parameter.value.apply_method, "immediate")
    }
  }

  tags = local.secondary_tags
}
