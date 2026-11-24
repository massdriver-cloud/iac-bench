# Optional: publish cluster upgrade and security-bulletin events to a
# module-created Pub/Sub topic so the platform team can wire alerts and
# automation off it.
resource "google_pubsub_topic" "upgrade_notifications" {
  count = var.enable_upgrade_notifications ? 1 : 0

  name    = "${var.cluster_name}-gke-upgrades"
  project = var.project_id
  labels  = var.labels
}
