# RDS requires a DB subnet group spanning at least two AZs. Explicit placement
# keeps the two instances in each region from sharing an AZ.
data "aws_subnet" "primary" {
  for_each = toset(data.aws_subnets.primary.ids)
  id       = each.value
}
data "aws_subnet" "secondary" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary.ids)
  id       = each.value
}
locals {
  primary_azs   = sort(distinct([for subnet in data.aws_subnet.primary : subnet.availability_zone]))
  secondary_azs = sort(distinct([for subnet in data.aws_subnet.secondary : subnet.availability_zone]))
}
