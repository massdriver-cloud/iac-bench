# Smallest valid instantiation: one production cluster in the apps-prod VPC.
#
# project_id is intentionally omitted: the module defaults to the project the
# provider/credentials are configured for, which is where the network team's
# VPCs live. Set it explicitly only when the state's project differs.

cluster_name = "apps-prod-main"
region       = "us-central1"
vpc_name     = "apps-prod"
