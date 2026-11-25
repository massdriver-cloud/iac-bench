# -----------------------------------------------------------------------------
# Workload Identity bindings
# -----------------------------------------------------------------------------
# Workloads reach Google services (Pub/Sub, Cloud Storage, Cloud SQL, ...) by
# impersonating a Google service account. This resource grants exactly that
# impersonation to one Kubernetes service account, so teams never distribute
# JSON keys and the node identity never accumulates workload roles.
#
# The Google service account itself is owned by the platform or product teams
# and must already exist in project_id; grant it the service-specific roles
# (e.g. roles/pubsub.publisher, roles/cloudsql.client) separately.

resource "google_service_account_iam_binding" "workload_identity" {
  for_each = var.workload_identity_bindings

  service_account_id = format("projects/%s/serviceAccounts/%s", var.project_id, each.value.google_service_account)
  role               = "roles/iam.workloadIdentityUser"

  members = [
    format(
      "serviceAccount:%s.svc.id.goog[%s/%s]",
      var.project_id,
      each.value.namespace,
      each.value.kubernetes_service_account,
    ),
  ]
}
