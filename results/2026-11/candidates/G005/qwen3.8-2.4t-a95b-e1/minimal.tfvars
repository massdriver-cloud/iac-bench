# Smallest valid instantiation of the GKE Standard platform module:
# one production cluster in the apps-prod VPC, one default node pool,
# all platform defaults (private endpoint, REGULAR channel, managed NAT).

project_id   = "prj-platform-example"
cluster_name = "apps-prod-us-central1"
region       = "us-central1"
network      = "apps-prod"
