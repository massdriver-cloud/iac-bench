# Smallest valid instantiation of the module: only the four per-instance
# facts the module cannot know on its own. Everything else takes the
# DBA-team standard defined by the module's defaults.
#
# This example targets the apps-dev network (the dev environment's VPC,
# where private services access is already configured).
name       = "apps-dev-postgres-01"
project_id = "iacbench-sandbox"
region     = "us-central1"
network    = "projects/iacbench-sandbox/global/networks/apps-dev"
