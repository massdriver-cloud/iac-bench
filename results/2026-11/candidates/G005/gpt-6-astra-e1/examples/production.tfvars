# Illustrative values: replace project, CIDRs and repository with existing resources.
project_id             = "platform-prod-12345"
cluster_name           = "products-us1"
environment            = "prod"
region                 = "us-central1"
master_ipv4_cidr_block = "172.20.0.0/28"
node_locations         = ["us-central1-a", "us-central1-b", "us-central1-c"]
authorized_networks = [{
  display_name = "management-vpn"
  cidr_block   = "10.60.0.0/24"
}]
node_pools = {
  general = {
    min_nodes = 3
    max_nodes = 12
  }
  workers = {
    machine_type = "e2-standard-8"
    min_nodes    = 3
    max_nodes    = 18
    labels       = { workload = "batch" }
    taints       = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
  }
}
artifact_registry_repositories = {
  applications = {
    project_id = "platform-prod-12345"
    location   = "us-central1"
    repository = "applications"
  }
}
workload_identities = {
  orders-prod-worker = {
    namespace                  = "orders"
    kubernetes_service_account = "worker"
    project_roles              = ["roles/cloudsql.client"]
  }
}
