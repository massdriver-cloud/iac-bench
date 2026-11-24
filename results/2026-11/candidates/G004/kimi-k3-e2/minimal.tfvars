# Smallest valid instantiation of the module: a staging database for the
# "checkout" service. Everything else uses the module's production defaults:
# Aurora global database across us-east-1 (writer) and us-west-2 (standby),
# network discovered from the apps-staging VPC's tier=database subnets,
# encryption with per-region CMKs, IAM database authentication, RDS-managed
# master password in Secrets Manager, 14 days of backups.
name        = "checkout"
environment = "staging"
