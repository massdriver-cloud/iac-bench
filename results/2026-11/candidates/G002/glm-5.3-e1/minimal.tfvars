# Smallest valid instantiation of the module.
#
# One private-IP PostgreSQL 16 instance named "apps-dev-pg" in the apps-dev
# VPC, with every fleet standard applied by default: regional HA, SSD with
# auto-resize, daily backups with point-in-time recovery, IAM database
# authentication, TLS required, no public IP, deletion protection, query
# insights, maintenance on Sunday 03:00 UTC.
#
# The network is given as a self link here; a bare network name (e.g.
# "apps-dev") is resolved automatically when the plan runs against the real
# project.

project = "apps-project"
name    = "apps-dev-pg"
region  = "us-central1"
tier    = "db-custom-2-8192"
network = "projects/apps-project/global/networks/apps-dev"
