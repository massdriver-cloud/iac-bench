project_id                     = "example-gke-project"
environment                    = "staging"
region                         = "us-central1"
cluster_name                   = "example-cluster"
master_ipv4_cidr_block         = "172.20.0.0/28"
control_plane_authorized_cidrs = { office = "203.0.113.0/24" }
