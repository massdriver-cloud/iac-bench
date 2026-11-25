# The Aurora global database: ties the two regional clusters together and
# replicates writes from the primary region to the standby region
# asynchronously, with typically sub-second lag. This is what makes the
# business bar achievable:
#
#   RPO: on a regional outage you lose at most the last few seconds of writes
#        (bounded by replication lag, normally well under a second).
#   RTO: promoting the standby cluster to writer takes about a minute; the
#        service reconnects to the secondary region's endpoints and is serving
#        again within minutes.

resource "aws_rds_global_cluster" "this" {
  provider                  = aws.primary
  global_cluster_identifier = "${local.name}-global"
  engine                    = local.engine
  engine_version            = local.engine_version
  storage_encrypted         = true
  deletion_protection       = local.deletion_protection

  tags = {
    Name = "${local.name}-global"
  }
}
