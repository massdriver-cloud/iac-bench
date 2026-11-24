# The module is a root module and configures both AWS providers itself.
# Cloud credentials come from the environment; regions come from variables.

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.default_tags
  }
}
