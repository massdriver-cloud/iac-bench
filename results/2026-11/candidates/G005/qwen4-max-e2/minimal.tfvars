# Smallest valid instantiation: only the four cluster-specific inputs.
# Everything else (sizing, hardening, upgrades, observability) comes from the
# module's production-safe defaults.

project_id   = "acme-apps-staging"
environment  = "staging"
region       = "us-central1"
cluster_name = "shared-staging"
