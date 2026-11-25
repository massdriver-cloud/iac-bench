locals {
  name          = "${var.service_name}-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))

  # e.g. "16.4" -> "aurora-postgresql16"
  parameter_group_family = "aurora-postgresql${element(split(".", var.engine_version), 0)}"

  port = 5432

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = var.environment
      Component          = "aurora-postgresql-global"
      ManagedBy          = "opentofu"
      DataClassification = "confidential-customer-payment"
    },
    var.tags,
  )
}
