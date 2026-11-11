###############################################################################
# The APIs this module itself depends on.
#
# Cloud SQL Admin and Secret Manager are the module's own dependencies - the
# instance and the break-glass secret cannot exist without them - so the
# module turns them on in project_id instead of failing halfway through an
# apply with a confusing SERVICE_DISABLED error. Everything else, notably the
# VPC networks and private services access, belongs to the network team and
# is treated as a prerequisite that is never created here.
#
# disable_on_destroy = false: enabling an API is a project-wide side effect
# that outlives any single instance and must not be rolled back by a
# decommission.
###############################################################################

resource "google_project_service" "sqladmin" {
  count                      = var.enable_apis ? 1 : 0
  project                    = var.project_id
  service                    = "sqladmin.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "secretmanager" {
  count                      = var.enable_apis ? 1 : 0
  project                    = var.project_id
  service                    = "secretmanager.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}
