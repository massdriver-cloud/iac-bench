# ---------------------------------------------------------------------------
# Smallest valid instantiation of the module.
#
# Only the four variables without defaults are set here; everything else
# falls back to the production-ready defaults in variables.tf. Replace the
# values with your project / network details before applying.
# ---------------------------------------------------------------------------

project_id = "your-project-id"

# One of the US regions where the network team prepared a GKE subnetwork.
region = "us-central1"

cluster_name = "platform-prod-us-central1"

# The environment VPC owned by the network team. The module derives the
# subnetwork "apps-prod-gke-us-central1" from it (with "pods" and "services"
# secondary ranges), per the network team's naming convention.
network = "apps-prod"
