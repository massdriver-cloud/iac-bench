# -----------------------------------------------------------------------------
# Databases
#
# The DBAs decide which databases exist; the module keeps them declarative.
# Schema objects inside the databases are managed by the migration tooling
# of the owning team, not by this module.
# -----------------------------------------------------------------------------

resource "google_sql_database" "databases" {
  for_each = var.databases

  name      = each.key
  instance  = google_sql_database_instance.primary.name
  charset   = each.value.charset
  collation = each.value.collation
}
