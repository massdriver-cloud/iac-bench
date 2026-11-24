# Smallest valid instantiation: every optional variable falls back to the
# module's standard defaults (db-g1-small, zonal, us-central1, 20 GB PD_SSD
# with autoresize, backups + PITR on, private IP on apps-dev, IAM-only auth).

name        = "dbas-pg-dev-a"
environment = "dev"
