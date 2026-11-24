# =========================================================================
# Databases
# =========================================================================
# Only names. Encoding, collation and everything else that a DBA might want
# to be deliberate about stays a psql decision, applied with the DBA's own
# identity through IAM login.

resource "google_sql_database" "this" {
  for_each = var.databases

  project  = var.project
  instance = google_sql_database_instance.this.name
  name     = each.value
}
