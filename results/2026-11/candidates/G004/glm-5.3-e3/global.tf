###############################################################################
# The Aurora global database.
#
# This is the resource that meets the business bar: a primary cluster in one
# region whose storage layer replicates continuously to a second region over
# the AWS backbone. Replication lag is typically well under a second (RPO),
# and the standby runs real instances so promoting it takes about a minute
# (RTO) — serving from another region within minutes, having lost at most a
# few seconds of writes.
###############################################################################

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.global_cluster_identifier
  engine                    = local.engine
  engine_version            = var.engine_version

  # The global database enforces encryption across all of its members.
  storage_encrypted = true

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be two different regions — the whole point of this module is surviving the loss of one of them."
    }
  }
}
