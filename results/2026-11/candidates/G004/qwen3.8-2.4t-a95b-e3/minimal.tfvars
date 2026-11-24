# Smallest valid instantiation: the two things that are specific to the
# service. Everything else (regions, engine version, sizing, backups,
# hardening) is owned by the module via its defaults.
#
# Regions default to us-east-1 (primary) / us-west-2 (secondary); the module
# discovers the apps-staging VPCs and their tier=database subnets there.

name        = "checkout"
environment = "staging"

# Common optional overrides the platform team may want, for reference:
#
#   database_name           = "checkout"
#   primary_region          = "us-east-1"
#   secondary_region        = "us-west-2"
#   engine_version          = "17.9"
#   instance_class          = "db.r6g.large"
#   instances_per_cluster   = 2
#   backup_retention_days   = 14
#   allowed_security_group_ids = {
#     primary   = ["sg-..."]   # EKS node/pod SGs in the primary region
#     secondary = ["sg-..."]   # EKS node/pod SGs in the secondary region
#   }
