locals {
  # The network team owns one VPC per environment (apps-<environment>) with a
  # ready-made GKE subnet per US region (apps-<environment>-gke-<region>) that
  # carries the secondary ranges "pods" and "services". The module derives the
  # names from the environment and region inputs instead of asking engineers to
  # re-type them (and get them wrong).
  network    = "apps-${var.environment}"
  subnetwork = "apps-${var.environment}-gke-${var.region}"

  workload_identity_pool = "${var.project_id}.svc.id.goog"

  labels = merge(
    {
      "environment" = var.environment
      "managed-by"  = "gke-standard-module"
    },
    var.labels,
  )

  # GKE recurring maintenance windows are defined by a start/end timestamp
  # pair plus a WEEKLY recurrence; the calendar date of the timestamps is only
  # an anchor for the weekday and time of day, so fixed 2025 dates are fine.
  weekday_anchor = {
    MON = "2025-01-06"
    TUE = "2025-01-07"
    WED = "2025-01-08"
    THU = "2025-01-09"
    FRI = "2025-01-10"
    SAT = "2025-01-11"
    SUN = "2025-01-12"
  }

  maintenance_start = format(
    "%sT%02d:00:00Z",
    local.weekday_anchor[var.maintenance_window.day],
    var.maintenance_window.start_hour_utc,
  )

  maintenance_end = timeadd(local.maintenance_start, "${var.maintenance_window.duration_hours}h")
}
