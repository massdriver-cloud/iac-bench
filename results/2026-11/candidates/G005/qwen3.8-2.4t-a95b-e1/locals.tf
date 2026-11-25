locals {
  # Network team convention: one GKE subnet per region, named <vpc>-gke-<region>.
  subnetwork_name = coalesce(var.subnetwork_name, "${var.network}-gke-${var.region}")
  network_url     = "projects/${var.project_id}/global/networks/${var.network}"
  subnetwork_url  = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"

  # Workload Identity pool: Kubernetes service accounts in this cluster map to
  # Google service accounts in this project.
  workload_pool = "${var.project_id}.svc.id.goog"

  maintenance_recurrence = "FREQ=WEEKLY;BYDAY=${join(",", var.maintenance_window.days)}"

  # Service account IDs are limited to 30 characters.
  node_sa_id = substr("gke-${var.cluster_name}-nodes", 0, 30)

  # Least-privilege roles the node service account needs for GKE to operate
  # (logging, monitoring, image pull). Workload access to Pub/Sub, GCS,
  # Cloud SQL etc. is deliberately NOT granted here: workloads get their own
  # Google service accounts through Workload Identity.
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}
