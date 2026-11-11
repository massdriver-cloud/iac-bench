###############################################################################
# Break-glass access to the built-in `postgres` superuser.
#
# Cloud SQL creates a `postgres` superuser on every PostgreSQL instance. It
# cannot be deleted, and someone needs it at least once (to GRANT
# cloudsqlsuperuser to the first IAM logins). The standard therefore is:
#
#   * the password is generated (32 chars), never typed by a human;
#   * it is stored in Secret Manager with module labels, so access to it is
#     IAM-controlled and audited;
#   * it is NOT exposed as a Terraform output (outputs end up in CI logs);
#   * day-to-day access remains IAM-only.
#
# The password necessarily also exists in Terraform state; restrict state
# access the same way you restrict the secret (see README).
###############################################################################

resource "random_password" "postgres" {
  count = var.manage_postgres_password ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#%*+-_=:" # survives SQL, shell and URL handling
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "google_sql_user" "postgres" {
  count    = var.manage_postgres_password ? 1 : 0
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = "postgres"
  password = random_password.postgres[0].result

  # The built-in user cannot be deleted; on destroy we only forget it here.
  deletion_policy = "ABANDON"
}

resource "google_secret_manager_secret" "postgres_password" {
  count     = var.manage_postgres_password ? 1 : 0
  project   = var.project_id
  secret_id = local.postgres_password_secret_id
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "postgres_password" {
  count       = var.manage_postgres_password ? 1 : 0
  secret      = google_secret_manager_secret.postgres_password[0].id
  secret_data = random_password.postgres[0].result

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_iam_member" "postgres_password_reader" {
  for_each = toset(var.manage_postgres_password ? var.postgres_password_readers : [])

  project   = var.project_id
  secret_id = google_secret_manager_secret.postgres_password[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value

  depends_on = [google_project_service.secretmanager]
}
