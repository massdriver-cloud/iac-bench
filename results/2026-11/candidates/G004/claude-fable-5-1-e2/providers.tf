# Two regional providers: the primary (writer) region and the secondary
# (standby) region of the Aurora Global Database. Credentials come from the
# environment (IAM role / env vars); only the region is set here.

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
