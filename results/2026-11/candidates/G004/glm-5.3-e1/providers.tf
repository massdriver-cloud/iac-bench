# This module is applied directly as a root module and works across two
# regions: `primary_region` hosts the writable cluster and `secondary_region`
# hosts an always-on, continuously replicated warm standby (an Aurora Global
# Database). Losing a region therefore costs at most a few seconds of writes
# and a failover measured in minutes - see README.md.

provider "aws" {
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
