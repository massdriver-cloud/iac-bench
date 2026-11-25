# Two regions are required: the Aurora Global Database has a writer cluster in
# var.primary_region and a read-only (promotable) secondary in var.secondary_region.
# Credentials come from the environment (AWS_* variables, SSO profile, or IAM role).

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = merge(var.tags, {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Module      = "aurora-global-postgres"
    })
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = merge(var.tags, {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Module      = "aurora-global-postgres"
    })
  }
}
