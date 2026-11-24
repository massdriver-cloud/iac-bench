# Not the minimal instantiation: exercises every optional input so the whole
# module can be planned. Use minimal.tfvars as the starting point.
project_id         = "example-project"
network_project_id = "example-network-host"
name               = "orders"
environment        = "prod"
region             = "europe-west1"
zone               = "europe-west1-b"
database_version   = "POSTGRES_16"
tier               = "db-custom-4-16384"

disk_size_gb             = 100
disk_autoresize_limit_gb = 1000

allocated_ip_range = "cloudsql-prod"

backup_location       = "eu"
backup_retained_count = 60

deny_maintenance_period = {
  start_date = "11-20"
  end_date   = "12-05"
}

database_flags = {
  max_connections            = "400"
  log_min_duration_statement = "1000"
}

pgaudit_extra_classes = ["write"]

databases = {
  orders    = {}
  reporting = { collation = "C" }
}

iam_members = [
  "group:dba-team@example.com",
  "user:alice@example.com",
  "serviceAccount:orders-api@example-project.iam.gserviceaccount.com",
]

read_replicas = {
  a = {}
  b = { tier = "db-custom-2-7680", zone = "europe-west1-c" }
}

kms_key_name = "projects/example-project/locations/europe-west1/keyRings/cloudsql/cryptoKeys/orders"

labels = {
  team = "payments"
}
