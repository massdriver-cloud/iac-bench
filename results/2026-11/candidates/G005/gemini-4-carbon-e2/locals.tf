locals {
  vpc_name             = coalesce(var.vpc_name_override, "apps-${var.environment}")
  subnet_name          = coalesce(var.subnet_name_override, "${local.vpc_name}-gke-${var.region}")
  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  workload_identity_pool = "${var.project_id}.svc.id.goog"

  raw_node_sa_id = "gke-${var.cluster_name}-nodes"
  node_sa_account_id = (
    length(local.raw_node_sa_id) <= 30
    ? local.raw_node_sa_id
    : format(
      "gke-%s-%s",
      trimsuffix(substr(var.cluster_name, 0, 19), "-"),
      substr(sha256(var.cluster_name), 0, 6)
    )
  )

  default_node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
    "roles/autoscaling.metricsWriter",
  ]

  node_sa_roles = toset(concat(local.default_node_sa_roles, var.additional_node_service_account_roles))

  common_labels = merge(
    {
      managed_by  = "opentofu"
      environment = var.environment
      cluster     = var.cluster_name
    },
    var.labels
  )

  managed_workload_identities = {
    for k, wi in var.workload_identities : k => merge(wi, {
      account_id = (
        length("wi-${var.cluster_name}-${k}") >= 6 && length("wi-${var.cluster_name}-${k}") <= 30
        ? "wi-${var.cluster_name}-${k}"
        : format(
          "wi-%s-%s",
          trimsuffix(substr("${var.cluster_name}-${k}", 0, 20), "-"),
          substr(sha256("${var.cluster_name}/${k}"), 0, 6)
        )
      )
    })
    if wi.gcp_service_account_email == null
  }

  workload_identity_project_role_bindings = merge([
    for k, wi in var.workload_identities : {
      for role in toset(wi.project_roles) :
      "${k}:${role}" => {
        wi_key = k
        role   = role
      }
    }
  ]...)
}
