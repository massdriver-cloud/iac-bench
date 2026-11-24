# Smallest valid instantiation: just the service name and environment.
# Everything else — regions, engine version, instance sizing, backup
# retention, parameter hardening — comes from the module defaults.

name        = "checkout"
environment = "prod"
