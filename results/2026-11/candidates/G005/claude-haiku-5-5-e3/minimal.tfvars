project_id             = "example-platform-project"
name                   = "apps-prod-us-central1"
environment            = "prod"
region                 = "us-central1"
master_ipv4_cidr_block = "172.16.0.0/28"
kms_key_id             = "projects/example-platform-project/locations/us-central1/keyRings/gke/cryptoKeys/etcd-secrets"

master_authorized_networks = [
  {
    cidr_block   = "10.0.0.0/8"
    display_name = "corp-internal"
  },
]
