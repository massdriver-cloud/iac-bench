# The default provider is the primary region (where the writer starts out);
# the "secondary" alias is the disaster-recovery region. Credentials come from
# the environment.

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
