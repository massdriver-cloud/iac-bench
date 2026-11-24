###############################################################################
# Connecting
###############################################################################

output "global_writer_endpoint" {
  description = "Writer endpoint that follows the writer across regions. It keeps the same name after a failover, so nothing has to be reconfigured during an incident. Reachable only from a network with a route to the region currently hosting the writer."
  value       = aws_rds_global_cluster.this.endpoint
}

output "endpoints" {
  description = "Regional endpoints. Services connect to the endpoints of their own region: `reader` for read-only traffic, `cluster` for writes (in the region that is not currently the writer, writes on `cluster` are forwarded when write forwarding is enabled and the session sets apg_write_forward.consistency_mode)."
  value = {
    (var.primary_region) = {
      cluster = aws_rds_cluster.primary.endpoint
      reader  = aws_rds_cluster.primary.reader_endpoint
    }
    (var.secondary_region) = {
      cluster = aws_rds_cluster.secondary.endpoint
      reader  = aws_rds_cluster.secondary.reader_endpoint
    }
  }
}

output "port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = local.database_name
}

###############################################################################
# Access
###############################################################################

output "client_security_group_ids" {
  description = "Per region, the security group to attach to pods (EKS SecurityGroupPolicy) so they can reach the database."
  value = {
    (var.primary_region)   = aws_security_group.client_primary.id
    (var.secondary_region) = aws_security_group.client_secondary.id
  }
}

output "database_security_group_ids" {
  description = "Per region, the security group attached to the database cluster."
  value = {
    (var.primary_region)   = aws_security_group.db_primary.id
    (var.secondary_region) = aws_security_group.db_secondary.id
  }
}

output "iam_database_users" {
  description = "PostgreSQL users that can log in with IAM tokens. Create each one once, as the admin user: CREATE USER <name>; GRANT rds_iam TO <name>;"
  value       = local.iam_database_users
}

output "iam_connect_policy_arn" {
  description = "IAM policy that allows connecting as the iam_database_users in both regions. Attach it to your service's pod role (or list the role in iam_auth_role_names)."
  value       = aws_iam_policy.connect.arn
}

output "master_secret_arns" {
  description = "Per region, the Secrets Manager secret holding the break-glass administrator credentials (JSON with username and password)."
  value = {
    (var.primary_region) = aws_secretsmanager_secret.master.arn
    (var.secondary_region) = one([
      for r in aws_secretsmanager_secret.master.replica : replace(aws_secretsmanager_secret.master.arn, ":${var.primary_region}:", ":${r.region}:")
    ])
  }
}

###############################################################################
# Identity of what was built
###############################################################################

output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database."
  value       = aws_rds_global_cluster.this.id
}

output "cluster_arns" {
  description = "Per region, the ARN of the regional Aurora cluster."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.arn
    (var.secondary_region) = aws_rds_cluster.secondary.arn
  }
}

output "cluster_identifiers" {
  description = "Per region, the identifier of the regional Aurora cluster."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.cluster_identifier
    (var.secondary_region) = aws_rds_cluster.secondary.cluster_identifier
  }
}

output "kms_key_arns" {
  description = "Per region, the customer-managed key that encrypts the database, its backups, logs and secret."
  value = {
    (var.primary_region)   = aws_kms_key.primary.arn
    (var.secondary_region) = aws_kms_key.secondary.arn
  }
}

###############################################################################
# Runbook
###############################################################################

output "regional_failover_commands" {
  description = "Ready-to-run commands. `disaster` promotes the other region when the writer's region is down (minutes; loses at most the replication lag, normally under a second). `drill` swaps regions with zero data loss while both are healthy; rehearse it regularly. Commands are shown for the as-built layout; after a failover, swap the regions."
  value = {
    disaster = "aws rds failover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss"
    drill    = "aws rds switchover-global-cluster --region ${var.primary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
  }
}
