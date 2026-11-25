locals {
  name_prefix = "${var.service_name}-${var.environment}"
  vpc_name    = "apps-${var.environment}"

  global_cluster_id    = "${local.name_prefix}-global"
  primary_cluster_id   = "${local.name_prefix}-${var.primary_region}"
  secondary_cluster_id = "${local.name_prefix}-${var.secondary_region}"

  secondary_instance_class = coalesce(var.secondary_instance_class, var.instance_class)
  primary_is_serverless    = var.instance_class == "db.serverless"
  secondary_is_serverless  = local.secondary_instance_class == "db.serverless"

  db_iam_usernames = var.db_iam_usernames != null ? var.db_iam_usernames : [replace(var.service_name, "-", "_")]

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  engine_version         = data.aws_rds_engine_version.primary.version_actual
  parameter_group_family = data.aws_rds_engine_version.primary.parameter_group_family

  # Sorted distinct AZs backing the discovered database subnets in each region
  primary_azs   = sort(distinct([for s in data.aws_subnet.primary_db : s.availability_zone]))
  secondary_azs = sort(distinct([for s in data.aws_subnet.secondary_db : s.availability_zone]))

  primary_sns_topic_arn   = var.primary_alarm_sns_topic_arn != null ? var.primary_alarm_sns_topic_arn : aws_sns_topic.primary_alerts[0].arn
  secondary_sns_topic_arn = var.secondary_alarm_sns_topic_arn != null ? var.secondary_alarm_sns_topic_arn : aws_sns_topic.secondary_alerts[0].arn

  # Modern RDS CA certificate (4096-bit RSA, long validity)
  ca_cert_identifier = "rds-ca-rsa4096-g1"

  # Log exports supported by Aurora PostgreSQL (audit/connection logs + failed IAM auth attempts)
  cloudwatch_log_exports = ["postgresql", "iam-db-auth-error"]

  # Baseline cluster parameters tuned by database specialists for production customer/payment workloads
  base_cluster_parameters = [
    # Enforce TLS on every client connection (PCI-DSS requirement)
    {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "pending-reboot"
    },
    # Load pgaudit (compliance auditing) and pg_stat_statements (query observability)
    {
      name         = "shared_preload_libraries"
      value        = "pgaudit,pg_stat_statements"
      apply_method = "pending-reboot"
    },
    # pgaudit configuration: audit DDL & privilege changes; never log raw bind parameters (PII/PCI safety)
    {
      name         = "pgaudit.log"
      value        = var.pgaudit_log
      apply_method = "immediate"
    },
    {
      name         = "pgaudit.log_catalog"
      value        = "0"
      apply_method = "immediate"
    },
    {
      name         = "pgaudit.log_parameter"
      value        = "0"
      apply_method = "immediate"
    },
    # Session & operational audit logging
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
      name         = "log_lock_waits"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_min_duration_statement"
      value        = tostring(var.slow_query_log_ms)
      apply_method = "immediate"
    },
    {
      name         = "log_temp_files"
      value        = "0"
      apply_method = "immediate"
    },
    {
      name         = "log_autovacuum_min_duration"
      value        = "0"
      apply_method = "immediate"
    },
    # Operational safety guardrails for microservice workloads
    {
      name         = "statement_timeout"
      value        = tostring(var.statement_timeout_ms)
      apply_method = "immediate"
    },
    {
      name         = "idle_in_transaction_session_timeout"
      value        = tostring(var.idle_in_transaction_timeout_ms)
      apply_method = "immediate"
    },
    {
      name         = "lock_timeout"
      value        = tostring(var.lock_timeout_ms)
      apply_method = "immediate"
    },
    # Query performance tracking
    {
      name         = "pg_stat_statements.track"
      value        = "all"
      apply_method = "immediate"
    },
    {
      name         = "pg_stat_statements.max"
      value        = "10000"
      apply_method = "pending-reboot"
    }
  ]

  # Merge extra_cluster_parameters so caller overrides replace matching baseline parameter names
  extra_param_names = toset([for p in var.extra_cluster_parameters : p.name])
  cluster_parameters = concat(
    [for p in local.base_cluster_parameters : p if !contains(local.extra_param_names, p.name)],
    var.extra_cluster_parameters
  )

  common_tags = merge(
    {
      service             = var.service_name
      environment         = var.environment
      owner               = var.owner_team
      data-classification = var.data_classification
      managed-by          = "opentofu"
      component           = "aurora-postgresql-global"
    },
    var.additional_tags
  )
}
