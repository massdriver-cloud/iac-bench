# Smallest valid instantiation of the module. Replace the project with the
# Google Cloud project that owns the cluster and the VPC.

project_id = "apps-prod-123456"

name    = "prod-us-central1"
region  = "us-central1"
network = "apps-prod" # subnet "apps-prod-gke-us-central1" is used automatically

# Everything else — node pools, release channel, maintenance window, security
# posture, observability — comes from the module's production defaults.
