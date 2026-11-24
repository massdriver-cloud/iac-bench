# Smallest valid instantiation of the module: every required variable gets a
# literal value, everything else runs on the module's standard defaults.
# Plans cleanly on its own.

name        = "apps-db"
region      = "us-central1"
environment = "dev"
tier        = "db-custom-2-7680"

# Self link of the dev VPC. Private services access is already configured on
# it by the network team.
network = "projects/example-project/global/networks/apps-dev"
