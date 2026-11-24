# Smallest valid instantiation: the production database for the checkout
# service. us-east-1 is the read-write region; if it fails, us-west-2 takes
# over. The module finds the apps-prod VPC and its tier=database subnets in
# both regions.
service_name     = "checkout"
environment      = "prod"
primary_region   = "us-east-1"
secondary_region = "us-west-2"
