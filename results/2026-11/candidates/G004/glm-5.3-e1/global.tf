# The Aurora global database ties the two regional clusters together with
# continuous, asynchronous storage replication. Typical replication lag is
# under a second (business bar: "no more than a few seconds of lost writes")
# and a managed failover completes in well under a minute (business bar:
# "serving again within minutes").
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.name}-global"
  engine                    = local.engine
  engine_version            = local.engine_version

  # These databases hold customer and payment data.
  storage_encrypted   = true
  deletion_protection = local.deletion_protection

  # Detach any remaining member clusters at destroy time so teardown never
  # wedges on global-cluster membership.
  force_destroy = true

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different: an Aurora global database always spans two distinct regions."
    }
  }
}
