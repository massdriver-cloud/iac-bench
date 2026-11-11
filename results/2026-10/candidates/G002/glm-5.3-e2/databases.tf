###############################################################################
# Databases on the primary (replicas receive them through replication)
###############################################################################

resource "google_sql_database" "databases" {
  for_each = var.databases

  project   = var.project_id
  instance  = google_sql_database_instance.primary.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}
