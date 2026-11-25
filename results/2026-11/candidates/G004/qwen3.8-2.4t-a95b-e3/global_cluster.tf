# ---------------------------------------------------------------------------
# Aurora Global Database
#
# The global cluster ties the primary (writable) cluster and the secondary
# (read-only) cluster together. Aurora replicates writes from the primary
# region to the secondary region continuously, typically with less than one
# second of lag:
#
#   * regional outage  -> promote the secondary cluster; service is back in
#     minutes having lost at most a few seconds of writes
#   * planned move     -> `rds:FailoverGlobalCluster` fails over with zero
#     data loss
#
# See README.md for the runbook.
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.stack
  engine                    = local.engine
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}
