# Smallest valid instantiation of the module.
#
# The only inputs without defaults are the service this database is for and
# the environment it lives in; everything else - regions, engine version,
# instance sizing, encryption, backups, monitoring - uses the module's
# production defaults.
#
# The network team's "apps-staging" VPCs, with their private tier=database
# subnets, are discovered by tag in both regions.

service_name = "checkout"
environment  = "staging"

# Regions default to the pair the platform runs EKS in; shown for clarity.
primary_region   = "us-east-1"
secondary_region = "us-west-2"
