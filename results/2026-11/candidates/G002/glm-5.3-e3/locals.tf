locals {
  # Standard labels on every instance. User labels are merged first so the
  # standards cannot be overwritten per instance.
  user_labels = merge(
    var.labels,
    {
      environment = var.environment
      managed_by  = "opentofu"
    },
  )

  # Cloud SQL wants the VPC as a self link. A bare network name is expanded
  # against var.project (the instance lives in the same project as the
  # networks); anything containing a slash - a project-relative path or a
  # full self link - is passed through untouched, which also covers a
  # network in another project if private services access allows it.
  private_network = can(regex("/", var.network)) ? var.network : "projects/${var.project}/global/networks/${var.network}"
}
