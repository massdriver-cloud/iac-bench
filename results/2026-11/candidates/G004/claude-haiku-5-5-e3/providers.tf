# Two explicit regional providers. Every regional resource names its provider
# explicitly so that nothing silently lands in the wrong region.
#
# The provider regions come from variables, so this root module is planned and
# applied directly with the region values from the tfvars file.

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
