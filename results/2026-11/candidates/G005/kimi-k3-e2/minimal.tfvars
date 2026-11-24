# Smallest valid instantiation of the module.
#
# Creates a regional, production-grade GKE Standard cluster in us-central1,
# attached to the network team's "apps-staging" VPC via the existing
# "apps-staging-gke-us-central1" subnetwork (secondary ranges "pods" /
# "services"). project_id is intentionally omitted: it defaults to the
# project configured in the provider/environment credentials.

name                   = "platform-staging"
region                 = "us-central1"
network                = "apps-staging"
master_ipv4_cidr_block = "172.16.0.0/28"
