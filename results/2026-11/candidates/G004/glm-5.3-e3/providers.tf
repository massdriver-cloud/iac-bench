###############################################################################
# Providers
#
# This module is applied as a root module, so the two regional providers are
# configured here and every resource pins the provider it needs explicitly.
# Credentials (and any assume-role chain) come from the environment.
###############################################################################

provider "aws" {
  alias = "primary"

  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias = "secondary"

  region = var.secondary_region

  default_tags {
    tags = local.common_tags
  }
}
