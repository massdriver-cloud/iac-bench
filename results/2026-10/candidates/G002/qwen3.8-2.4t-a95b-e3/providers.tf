# This module is intended to be applied directly as a root module by the DBA
# team, so it configures its own provider.
#
# `project` is optional: when null, the provider falls back to the project of
# the ambient credentials (GOOGLE_PROJECT / service-account key), which is how
# the team works day-to-day. `region` is per-instance.
provider "google" {
  project = var.project
  region  = var.region
}
