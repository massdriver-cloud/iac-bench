# -----------------------------------------------------------------------------
# Engine Version Discovery & Hardened PostgreSQL Parameter Groups
# -----------------------------------------------------------------------------

data "aws_rds_engine_version" "primary" {
  region  = var.primary_region
  engine  = "aurora-postgresql"
  version = coalesce(var.engine_version, var.engine_major_version)
  latest  = var.engine_version == null ? true : null
}

data "aws_rds_engine_version" "secondary" {
  region  = var.secondary_region
  engine  = "aurora-postgresql"
  version = data.aws_rds_engine_version.primary.version_actual
}

locals {
  engine_version         = data.aws_rds_engine_version.primary.version_actual
  parameter_group_family = data.aws_rds_engine_version.primary.parameter_group_family

  baseline_cluster_parameters = {
    "rds.force_ssl" = {
      value        = "1"
      apply_method = "pending-reboot"
    }
    "ssl_min_protocol_version" = {
      value        = "TLSv1.2"
      apply_method = "immediate"
    }
    "shared_preload_libraries" = {
      value        = "pg_stat_statements,pgaudit"
      apply_method = "pending-reboot"
    }
    "pgaudit.log" = {
      value        = "ddl,role"
      apply_method = "immediate"
    }
    "pg_stat_statements.track" = {
      value        = "all"
      apply_method = "immediate"
    }
    "log_connections" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_disconnections" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_lock_waits" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_min_duration_statement" = {
      value        = "1000"
      apply_method = "immediate"
    }
    "idle_in_transaction_session_timeout" = {
      value        = "60000"
      apply_method = "immediate"
    }
  }

  caller_cluster_parameters = {
    for p in var.cluster_parameters : p.name => {
      value        = p.value
      apply_method = p.apply_method
    }
    if p.name != "rds.force_ssl"
  }

  effective_cluster_parameters = merge(
    local.baseline_cluster_parameters,
    local.caller_cluster_parameters,
  )

  instance_parameters = {
    "tcp_keepalives_idle" = {
      value        = "60"
      apply_method = "immediate"
    }
    "tcp_keepalives_interval" = {
      value        = "10"
      apply_method = "immediate"
    }
    "tcp_keepalives_count" = {
      value        = "6"
      apply_method = "immediate"
    }
  }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  region      = var.primary_region
  name_prefix = "${local.primary_cluster_id}-cpg-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameters for ${var.service_name} (${local.env_short}) in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-cpg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "primary" {
  region      = var.primary_region
  name_prefix = "${local.primary_cluster_id}-pg-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL instance parameters for ${var.service_name} (${local.env_short}) in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-pg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  region      = var.secondary_region
  name_prefix = "${local.secondary_cluster_id}-cpg-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameters for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-cpg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "secondary" {
  region      = var.secondary_region
  name_prefix = "${local.secondary_cluster_id}-pg-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL instance parameters for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-pg"
  })

  lifecycle {
    create_before_destroy = true
  }
}
