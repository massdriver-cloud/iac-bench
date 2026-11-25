# The provider's resolved project (explicit variable, else GOOGLE_PROJECT /
# credentials). google_client_config is a pure configuration lookup — it does
# not call the Google Cloud API — so plans stay fast and offline-friendly.
data "google_client_config" "current" {}

locals {
  project_id = coalesce(var.project_id, data.google_client_config.current.project)

  # Network team conventions, enforced by the module:
  #  - one VPC per environment (e.g. "apps-prod")
  #  - one GKE subnet per region: "<vpc>-gke-<region>"
  #  - secondary ranges named "pods" and "services"
  network_name    = var.vpc_name
  subnetwork_name = "${var.vpc_name}-gke-${var.region}"
  pods_range      = "pods"
  services_range  = "services"

  workload_pool = "${local.project_id}.svc.id.goog"

  cluster_labels = merge(
    { managed-by = "opentofu" },
    var.labels,
  )

  # Service account ids are capped at 30 characters.
  node_service_account_id = substr("gke-${substr(var.cluster_name, 0, 23)}-np", 0, 30)

  # Minimal roles a GKE node needs: log/metric shipping, metadata, and pulling
  # images. Deliberately NOT the Compute Engine default service account.
  node_service_account_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  upgrade_notifications_topic = var.upgrade_notifications_topic == null ? null : (
    can(regex("^projects/", var.upgrade_notifications_topic))
    ? var.upgrade_notifications_topic
    : "projects/${local.project_id}/topics/${var.upgrade_notifications_topic}"
  )
}
