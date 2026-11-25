# The primary region is the default provider. The secondary region uses an
# alias. Both get credentials from the environment (AWS_* variables or an
# attached IAM role); nothing is hard-coded here.

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
