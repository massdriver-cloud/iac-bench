# Smallest valid instantiation of the module.
#
# These three values are the only things the owning service team must decide:
# who the database is for, which environment's network it lives in, and how
# big it is. Everything else has a production-safe default (see variables.tf).
#
#   tofu plan  -var-file=minimal.tfvars
#   tofu apply -var-file=minimal.tfvars

service_name   = "checkout"
environment    = "staging"
instance_class = "db.t4g.medium"
