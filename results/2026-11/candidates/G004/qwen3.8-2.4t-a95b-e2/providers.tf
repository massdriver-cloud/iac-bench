# The default provider targets the PRIMARY region: home of the global database's
# read-write cluster. Credentials come from the ambient environment (the
# platform pipelines and EKS workloads reach AWS through IAM roles), so no
# credential material is declared here.
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

# The aliased provider targets the SECONDARY region: home of the warm standby
# cluster that is promoted if the primary region fails.
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.common_tags
  }
}
