project_id             = "apps-prod-platform"
name                   = "prod-central"
environment            = "prod"
region                 = "us-central1"
control_plane_ipv4_cidr = "172.20.0.0/28"
authorized_networks    = { platform = "10.20.0.0/24" }
node_locations         = ["us-central1-a", "us-central1-b", "us-central1-c"]
workload_identities = {
  orders = {
    namespace       = "orders-prod"
    service_account = "orders-api"
    project_roles   = ["roles/cloudsql.client"]
  }
}
artifact_registry_repositories = {
  apps = { project = "apps-prod-platform", location = "us-central1", repository = "apps" }
}
