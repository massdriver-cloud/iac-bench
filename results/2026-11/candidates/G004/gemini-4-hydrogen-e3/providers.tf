provider "aws" {
  region = var.primary_region

  default_tags {
    tags = merge(
      {
        Service            = var.service_name
        Environment        = var.environment
        ManagedBy          = "opentofu"
        DataClassification = "confidential-payment"
      },
      var.tags,
    )
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = merge(
      {
        Service            = var.service_name
        Environment        = var.environment
        ManagedBy          = "opentofu"
        DataClassification = "confidential-payment"
      },
      var.tags,
    )
  }
}
