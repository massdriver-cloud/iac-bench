locals {
  # The fleet pins exactly one flag: Cloud SQL IAM database authentication is
  # the only authentication path this module allows, so its flag is always on
  # and cannot be turned off per instance. DBA-supplied flags are merged on
  # top of it.
  database_flags = merge(
    { "cloudsql.iam_authentication" = "on" },
    var.database_flags,
  )

  network_is_self_link = can(regex("^(https?://|projects/)", var.network))

  # A bare network name is resolved through a data source in main.tf; a self
  # link is used verbatim.
  private_network = local.network_is_self_link ? var.network : try(data.google_compute_network.selected[0].self_link, var.network)

  # Cloud SQL's maintenance window day is a number 1-7, Monday = 1. The module
  # takes day names, because nobody should have to remember that.
  maintenance_window_day = {
    MONDAY    = 1
    TUESDAY   = 2
    WEDNESDAY = 3
    THURSDAY  = 4
    FRIDAY    = 5
    SATURDAY  = 6
    SUNDAY    = 7
  }

  # Every Google identity the module wires up for database access, as
  # email -> IAM principal type prefix. Used for the project-level role grants.
  iam_principals = merge(
    { for email in var.iam_database_users : email => "user" },
    { for email in var.iam_database_groups : email => "group" },
    { for email in var.iam_service_accounts : email => "serviceAccount" },
  )
}
