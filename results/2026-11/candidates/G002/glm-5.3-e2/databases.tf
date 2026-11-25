# Databases on the primary instance.
#
# Removing an entry from var.databases only makes Terraform forget the
# database (deletion_policy = ABANDON); dropping data is always a deliberate,
# out-of-band act. See the README runbook.

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = var.project
  instance  = google_sql_database_instance.primary.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation

  deletion_policy = "ABANDON"
}
