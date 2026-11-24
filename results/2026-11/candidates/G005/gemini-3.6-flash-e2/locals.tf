locals {
  subnet_name = var.subnet_name != null && var.subnet_name != "" ? var.subnet_name : "${var.network}-gke-${var.region}"

  node_service_account_email = var.create_service_account ? google_service_account.gke_node_sa[0].email : var.service_account

  default_labels = merge(
    {
      "managed-by" = "opentofu"
      "module"     = "gke-standard"
    },
    var.labels
  )
}
