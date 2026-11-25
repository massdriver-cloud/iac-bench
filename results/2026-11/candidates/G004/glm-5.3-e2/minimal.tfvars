# Smallest valid instantiation of the module: the staging deployment of the
# "checkout" service database. Every other input uses the module defaults:
#
#   - primary region us-east-1, secondary (failover) region us-west-2
#   - database subnets discovered from the network team's apps-staging VPC
#     (subnets tagged tier = database)
#   - default Aurora PostgreSQL engine version
#   - staging defaults: 1 instance per region, 7-day backups, no deletion
#     protection, no final snapshot
#   - ingress allowed from the VPC CIDR; set allowed_security_group_ids to pin
#     access to your EKS security groups
#
# See README.md for a production-grade instantiation.

name          = "checkout"
database_name = "checkout"
environment   = "staging"
