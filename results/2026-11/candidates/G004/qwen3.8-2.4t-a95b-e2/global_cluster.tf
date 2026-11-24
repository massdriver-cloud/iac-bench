# The replication fabric for cross-region disaster recovery. An Aurora Global
# Database replicates at the storage layer with typically less than one second
# of lag, which is what makes "serving from another region within minutes,
# having lost no more than a few seconds of writes" achievable: a failover
# promotes an already-warm cluster instead of restoring from backups.
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.global_cluster_identifier
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}
