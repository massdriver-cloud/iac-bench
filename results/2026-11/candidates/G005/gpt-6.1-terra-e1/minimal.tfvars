project_id             = "example-gke-project"
cluster_name           = "production-cluster"
environment            = "prod"
region                 = "us-central1"
zones                  = ["us-central1-a", "us-central1-b", "us-central1-c"]
master_ipv4_cidr_block = "172.16.0.0/28"
admin_cidrs            = ["10.20.0.0/24"]
