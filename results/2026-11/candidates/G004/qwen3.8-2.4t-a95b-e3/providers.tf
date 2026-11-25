# The module operates in two regions at once: the primary region holds the
# writable Aurora cluster and the secondary region holds a read-only cluster
# that Aurora Global Database continuously replicates to (typically < 1s of
# lag). The providers live here at the root so the regions are plain inputs.

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
