data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_partition" "current" {
  provider = aws.primary
}

data "aws_rds_engine_version" "postgresql" {
  provider = aws.primary
  engine   = "aurora-postgresql"
  version  = var.engine_version
  latest   = true
}

data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
}

data "aws_subnets" "primary_database" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    tier = "database"
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    tier = "database"
  }
}

locals {
  name_prefix   = "${var.service_name}-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  app_db_users  = length(var.app_db_usernames) > 0 ? var.app_db_usernames : [replace(var.service_name, "-", "_")]

  primary_cidr_blocks = distinct(concat(
    [data.aws_vpc.primary.cidr_block],
    coalesce(try(var.allowed_cidr_blocks.primary, null), [])
  ))

  secondary_cidr_blocks = distinct(concat(
    [data.aws_vpc.secondary.cidr_block],
    coalesce(try(var.allowed_cidr_blocks.secondary, null), [])
  ))

  primary_security_group_ids   = distinct(coalesce(try(var.allowed_security_group_ids.primary, null), []))
  secondary_security_group_ids = distinct(coalesce(try(var.allowed_security_group_ids.secondary, null), []))

  default_cluster_parameters = {
    "rds.force_ssl"                       = { value = "1", apply_method = "immediate" }
    "shared_preload_libraries"            = { value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
    "pgaudit.log"                         = { value = "ddl,role", apply_method = "immediate" }
    "pgaudit.log_catalog"                 = { value = "0", apply_method = "immediate" }
    "pgaudit.log_parameter"               = { value = "0", apply_method = "immediate" }
    "log_connections"                     = { value = "1", apply_method = "immediate" }
    "log_disconnections"                  = { value = "1", apply_method = "immediate" }
    "log_checkpoints"                     = { value = "1", apply_method = "immediate" }
    "log_lock_waits"                      = { value = "1", apply_method = "immediate" }
    "log_min_duration_statement"          = { value = "1000", apply_method = "immediate" }
    "idle_in_transaction_session_timeout" = { value = "60000", apply_method = "immediate" }
    "track_activity_query_size"           = { value = "4096", apply_method = "pending-reboot" }
    "pg_stat_statements.track"            = { value = "ALL", apply_method = "immediate" }
    "rds.logical_replication"             = { value = "0", apply_method = "pending-reboot" }
  }

  user_cluster_parameters = {
    for p in var.cluster_parameters : p.name => {
      value        = p.value
      apply_method = coalesce(p.apply_method, "immediate")
    }
  }

  merged_cluster_parameters = merge(local.default_cluster_parameters, local.user_cluster_parameters)

  default_instance_parameters = {
    "log_temp_files" = { value = "0", apply_method = "immediate" }
  }

  user_instance_parameters = {
    for p in var.instance_parameters : p.name => {
      value        = p.value
      apply_method = coalesce(p.apply_method, "immediate")
    }
  }

  merged_instance_parameters = merge(local.default_instance_parameters, local.user_instance_parameters)

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = var.environment
      ManagedBy          = "opentofu"
      DataClassification = "confidential-pci-pii"
      DatabaseEngine     = "aurora-postgresql"
    },
    var.tags
  )
}
