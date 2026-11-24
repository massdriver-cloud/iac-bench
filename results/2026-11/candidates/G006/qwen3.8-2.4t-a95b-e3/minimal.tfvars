# Smallest valid instantiation of the module.
#
# The standard usage for an application team passes its existing resource
# group instead (see README.md), e.g.:
#
#   resource_group_name = "orders-staging"
#
# With no resource_group_name, the module creates the conventional
# "orders-staging" group, which makes `location` mandatory.

application = "orders"
environment = "staging"
location    = "westeurope"
