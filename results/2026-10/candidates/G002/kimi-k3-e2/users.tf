# IAM principals as database users. Humans authenticate as themselves (or via
# an audited group), workloads as their service account — no shared passwords.
resource "google_sql_user" "iam" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  type     = each.value.type

  # Cloud SQL requires service-account usernames without the
  # ".gserviceaccount.com" suffix; accept the full email and trim it here so
  # callers can always pass the principal's real email address.
  name = each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(each.value.email, ".gserviceaccount.com") : each.value.email
}
