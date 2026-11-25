# Two aliased providers: one per region of the Aurora Global Database.
# Credentials are supplied by the environment (shared credentials file,
# env vars, or the ambient IAM role).

provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.common_tags
  }
}
