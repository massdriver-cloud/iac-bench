# One provider per region. Every resource in this module names its provider
# explicitly, so it is always obvious which region a resource lands in.

provider "aws" {
  alias  = "primary"
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
