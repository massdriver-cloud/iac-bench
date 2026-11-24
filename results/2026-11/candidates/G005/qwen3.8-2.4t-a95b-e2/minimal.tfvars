# Smallest valid instantiation: one cluster in the apps-staging environment.
# Only the four cluster-specific inputs are required; the module supplies
# production-ready defaults for everything else.
project_id   = "apps-platform"
cluster_name = "apps-staging-shared"
region       = "us-central1"
network_name = "apps-staging"
