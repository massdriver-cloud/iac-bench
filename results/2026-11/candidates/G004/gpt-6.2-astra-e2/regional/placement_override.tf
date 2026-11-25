# Constrain Aurora placement to the tagged DB subnet zones; fail if fewer than two exist.
resource "aws_rds_cluster_instance" "db" {
  availability_zone = local.zones[count.index]
}
