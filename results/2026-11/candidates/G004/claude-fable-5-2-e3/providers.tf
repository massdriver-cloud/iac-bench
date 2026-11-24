# Two regional provider configurations. "primary" is the region that hosts the
# writer on day one; "secondary" is the warm standby region. After a failover
# the roles swap at the Aurora level, but the provider mapping stays the same.

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.tags
  }
}
