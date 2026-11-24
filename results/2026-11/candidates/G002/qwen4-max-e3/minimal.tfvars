# Smallest valid instantiation: one dev PostgreSQL instance.
# Only the decisions that are genuinely the DBAs' are supplied; everything
# else is the team standard baked into the module.

instance_name = "pg-minimal-dev"
environment   = "dev"
region        = "us-central1"
tier          = "db-custom-2-7680"
database_name = "app"

# Disposable minimal/test instance: allow teardown. Real instances keep the
# module default (true).
deletion_protection = false
