###############################################################################
# Databases.
#
# Databases hold data that outlives Terraform configuration: removing one from
# var.databases abandons it (removes it from state, leaves it on the
# instance) instead of dropping it. Dropping a database is a deliberate SQL
# operation performed by a DBA, not a side effect of editing a map.
###############################################################################

resource "google_sql_database" "this" {
  for_each  = var.databases
  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation

  deletion_policy = "ABANDON"
}
