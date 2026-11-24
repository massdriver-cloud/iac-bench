# Two regional providers: the primary (writer) region and the secondary
# (disaster-recovery) region. Credentials come from the environment.

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
