# Smallest valid instantiation of the module: a staging cluster in
# us-central1, attached to the network team's apps-staging VPC and its
# apps-staging-gke-us-central1 subnet. Every other variable uses the
# module's production defaults.

project_id             = "iacbench-sandbox"
name                   = "apps-staging-usc1"
region                 = "us-central1"
vpc_name               = "apps-staging"
master_ipv4_cidr_block = "172.16.0.0/28"
