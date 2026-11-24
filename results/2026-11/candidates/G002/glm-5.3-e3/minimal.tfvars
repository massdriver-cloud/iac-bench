# Smallest valid instantiation: one standard instance on the dev network.
# Everything else in the module either has a standard default or is fixed
# by the standard itself (private IP only, IAM authentication, backups +
# point-in-time recovery, TLS required, deletion protection).

name             = "orders"
project          = "acme-apps"
environment      = "dev"
region           = "us-central1"
network          = "apps-dev"
database_version = "POSTGRES_16"
tier             = "db-custom-2-8192"
