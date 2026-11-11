# Smallest valid instantiation of the module: one standard PostgreSQL instance
# in the dev environment. Every other input takes its default from
# variables.tf; see README.md for the full picture.

name        = "orders-db"
project_id  = "acme-apps-dev"
region      = "us-central1"
environment = "dev"
